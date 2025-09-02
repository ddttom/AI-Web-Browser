import SwiftUI
import WebKit

// Web content view for displaying individual tabs
struct WebContentView: View {
    @ObservedObject var tab: Tab
    private let tabManager: TabManager
    @State private var pulsingScale: CGFloat = 1.0
    @State private var hoveredLink: String? = nil
    @State private var hasInitializedWebView: Bool = false
    @State private var showFloatingAssistant: Bool = false
    @StateObject private var aiAssistant: AIAssistant

    init(tab: Tab, tabManager: TabManager) {
        self._tab = ObservedObject(wrappedValue: tab)
        self.tabManager = tabManager
        self._aiAssistant = StateObject(wrappedValue: AIAssistant.shared)
    }

    var body: some View {
        // CRITICAL FIX: Use GeometryReader to ensure WebView responds to window size changes
        GeometryReader { geometry in
            ZStack {
                if tab.isHibernated, let snapshot = tab.snapshot {
                    // Show snapshot for hibernated tabs
                    Image(nsImage: snapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay(
                            VStack {
                                Text("Tab Hibernated")
                                    .font(.headline)
                                Text("Click to reload")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        )
                        .onTapGesture {
                            tab.wakeUp()
                        }
                } else {
                    // Active web view - create WebView for all tabs to ensure immediate responsiveness
                    // This ensures new tabs are ready for interaction even without an initial URL
                    ZStack {
                        // Always create WebView for responsiveness, even for new tabs
                        PersistentWebView(tab: tab, hoveredLink: $hoveredLink)
                            .id(tab.id)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .onAppear {
                                hasInitializedWebView = true
                            }
                            .opacity(tab.url != nil ? 1.0 : 0.0)  // Hide WebView for new tabs without URL
                            .animation(.easeInOut(duration: 0.3), value: tab.url != nil)  // Smooth transition

                        // Show NewTabView overlay for tabs without URL
                        if tab.url == nil {
                            NewTabView(tab: tab)
                                .onAppear {
                                    // WebView is actually initialized, just hidden behind NewTabView
                                    hasInitializedWebView = true
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                }

                // Enhanced loading progress bar positioned closer to top bar
                if tab.isLoading {
                    VStack(spacing: 0) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background track
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: 3)

                                // Main progress fill with default blue
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: geometry.size.width * progressPercent, height: 3)
                                    .animation(
                                        .easeOut(duration: 0.2), value: tab.estimatedProgress
                                    )
                                    .animation(.easeInOut(duration: 0.5), value: tab.themeColor)

                                // Progressive blur overlay - no blur at start, maximum at end
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.clear,  // No effect at start
                                                Color.clear,
                                                Color.blue.opacity(0.2),
                                                Color.blue.opacity(0.5),  // Max glow near end
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width * progressPercent, height: 6)
                                    .blur(radius: progressiveBlurRadius)
                                    .animation(
                                        .easeOut(duration: 0.2), value: tab.estimatedProgress)

                                // Enhanced progressive trailing glow
                                if tab.estimatedProgress > 0.3 {
                                    Rectangle()
                                        .fill(
                                            RadialGradient(
                                                colors: [
                                                    Color.blue.opacity(0.6),
                                                    Color.blue.opacity(0.3),
                                                    Color.blue.opacity(0.1),
                                                    Color.clear,
                                                ],
                                                center: .center,
                                                startRadius: 1,
                                                endRadius: 15
                                            )
                                        )
                                        .frame(width: 8, height: 8)
                                        .offset(x: geometry.size.width * progressPercent - 4, y: 1)
                                        .blur(radius: progressiveBlurRadius * 0.8)
                                        .scaleEffect(pulsingScale)
                                        .animation(
                                            .easeOut(duration: 0.2), value: tab.estimatedProgress)
                                }
                            }
                            .clipShape(Capsule())
                        }
                        .frame(height: 3)
                        .transition(.opacity.combined(with: .scale(scale: 1.0, anchor: .leading)))
                        .padding(.top, 0)  // No margin - positioned directly against top bar

                        Spacer()
                    }
                }

                // Smart Status Bar positioned at bottom-left
                VStack {
                    Spacer()
                    HStack {
                        SmartStatusBar(tab: tab, hoveredLink: hoveredLink)
                        Spacer()
                    }
                    .padding(.bottom, 16)
                    .padding(.leading, 16)
                }
                .allowsHitTesting(false)  // Don't interfere with web content interaction

                // Floating Assistant removed per UX refinement
            }
            // Force explicit frame to ensure WebView gets proper dimensions
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onReceive(tab.$isLoading) { isLoading in
            if isLoading {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsingScale = 1.5
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    pulsingScale = 1.0
                }
            }
        }
        .onAppear {
            Task { await aiAssistant.initialize() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .performTLDRRequested)) { _ in
            Task {
                _ = try? await aiAssistant.generatePageTLDR()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .performAskRequested)) {
            notification in
            if let question = notification.object as? String {
                Task {
                    _ = try? await aiAssistant.processQuery(
                        question, includeContext: true, includeHistory: true)
                }
            } else {
                NotificationCenter.default.post(name: .showCommandPaletteRequested, object: nil)
            }
        }
    }

    // Theme-aware progress color with fallback
    private var themeAwareProgressColor: Color {
        if let themeColor = tab.themeColor {
            let nsColor = themeColor
            // Convert to SwiftUI color and ensure good saturation
            let swiftColor = Color(nsColor)

            // Boost saturation for better visibility in progress bars
            let components = NSColor(swiftColor).usingColorSpace(.sRGB) ?? NSColor.blue
            let red = min(1.0, components.redComponent * 1.2)
            let green = min(1.0, components.greenComponent * 1.2)
            let blue = min(1.0, components.blueComponent * 1.2)

            return Color(red: red, green: green, blue: blue)
        }
        return Color.blue
    }

    // Progress as percentage for width calculation
    private var progressPercent: CGFloat {
        return CGFloat(SafeNumericConversions.safeProgress(tab.estimatedProgress))
    }

    // Progressive blur radius - starts at 0, increases dramatically toward end
    private var progressiveBlurRadius: CGFloat {
        let progress = SafeNumericConversions.safeProgress(tab.estimatedProgress)
        // Exponential curve: no blur at start (0-30%), dramatic increase at end (70-100%)
        if progress < 0.3 {
            return 0.0
        } else {
            let adjustedProgress = (progress - 0.3) / 0.7  // Map 0.3-1.0 to 0.0-1.0
            return pow(adjustedProgress, 2.0) * 12.0  // Quadratic curve, max 12pt blur
        }
    }
}

// Persistent WebView that maintains state per tab
struct PersistentWebView: View {
    @ObservedObject var tab: Tab
    @Binding var hoveredLink: String?

    var body: some View {
        // Only create a new WebView if the tab doesn't already have one
        Group {
            if tab.webView == nil {
                // Create new WebView and store it in the tab
                WebView(
                    url: Binding(
                        get: { tab.url },
                        set: { tab.url = $0 }
                    ),
                    canGoBack: Binding(
                        get: { tab.canGoBack },
                        set: { tab.canGoBack = $0 }
                    ),
                    canGoForward: Binding(
                        get: { tab.canGoForward },
                        set: { tab.canGoForward = $0 }
                    ),
                    isLoading: Binding(
                        get: { tab.isLoading },
                        set: { tab.isLoading = $0 }
                    ),
                    estimatedProgress: Binding(
                        get: { tab.estimatedProgress },
                        set: { tab.estimatedProgress = $0 }
                    ),
                    title: Binding(
                        get: { tab.title },
                        set: { tab.title = $0 ?? "New Tab" }
                    ),
                    favicon: Binding(
                        get: { tab.favicon },
                        set: { tab.favicon = $0 }
                    ),
                    hoveredLink: $hoveredLink,
                    mixedContentStatus: .constant(nil),
                    tab: tab,
                    onNavigationAction: nil,
                    onDownloadRequest: nil
                )
                .id(tab.id)
                // URL updates now handled by URLSynchronizer - no manual URL string updates needed
            } else {
                // Use existing WebView wrapped in a NSViewRepresentable
                ExistingWebView(tab: tab)
                    .id(tab.id)
                // URL updates now handled by URLSynchronizer - no manual URL string updates needed
            }
        }
    }
}

// Wrapper for existing WebView instances
struct ExistingWebView: NSViewRepresentable {
    @ObservedObject var tab: Tab

    typealias NSViewType = WKWebView

    func makeNSView(context: Context) -> WKWebView {
        guard let webView = tab.webView else {
            fatalError("ExistingWebView called but tab.webView is nil for tab \(tab.id)")
        }

        // Store tab ID in webView for ownership validation
        context.coordinator.tabId = tab.id

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // CRITICAL: Validate WebView ownership to prevent content bleeding between tabs
        guard context.coordinator.tabId == tab.id else {
            print(
                "⚠️ WebView ownership mismatch detected! WebView belongs to tab \(context.coordinator.tabId ?? UUID()) but being used by tab \(tab.id)"
            )
            return  // Abort update to prevent cross-tab contamination
        }

        // Additional safety: Only update if this WebView actually belongs to this tab
        guard webView === tab.webView else {
            print("⚠️ WebView instance mismatch detected for tab \(tab.id)")
            return  // Prevent state updates from wrong WebView instance
        }

        // CRITICAL FIX: Update WKWebView frame when SwiftUI container size changes
        // This ensures the WebView expands properly during window resize
        DispatchQueue.main.async {
            if let containerView = webView.superview {
                let newFrame = containerView.bounds
                if !webView.frame.equalTo(newFrame) {
                    webView.frame = newFrame

                    // Force WebKit to update its viewport for the new frame
                    webView.evaluateJavaScript(
                        """
                        if (window.dispatchEvent) {
                            window.dispatchEvent(new Event('resize'));
                        }
                        """
                    ) { _, error in
                        if let error = error {
                            if AppLog.isVerboseEnabled {
                                AppLog.debug(
                                    "Failed to dispatch resize: \(error.localizedDescription)")
                            }
                        }
                    }

                    NSLog("🔄 WebView frame updated for tab \(self.tab.id): \(newFrame)")
                }
            }
        }

        // SIMPLIFIED: Only navigate if WebView has no URL to avoid interference with WebKit's navigation flow
        if let tabURL = tab.url, webView.url == nil {
            let request = URLRequest(url: tabURL)
            webView.load(request)
        }

        // Simplified property sync - URLSynchronizer handles URL updates through WebView delegates
        DispatchQueue.main.async {
            // Double-check ownership before updating properties
            guard webView === self.tab.webView else { return }

            self.tab.canGoBack = webView.canGoBack
            self.tab.canGoForward = webView.canGoForward
            self.tab.isLoading = webView.isLoading
            self.tab.estimatedProgress = webView.estimatedProgress
            self.tab.title = webView.title ?? "New Tab"

            // URL updates are now handled automatically by URLSynchronizer through WebView observers
            // This prevents race conditions and ensures consistent URL state management
        }
    }

    func makeCoordinator() -> ExistingWebViewCoordinator {
        ExistingWebViewCoordinator()
    }

    class ExistingWebViewCoordinator: NSObject {
        var tabId: UUID?
    }
}
