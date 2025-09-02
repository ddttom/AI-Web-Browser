import Combine
import SwiftUI

/// AI Assistant sidebar with collapsible right panel interface
/// Provides context-aware chat with glass morphism styling
struct AISidebar: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject private var contextManager = ContextManager.shared
    @ObservedObject private var providerManager = AIProviderManager.shared
    @StateObject private var aiAssistant: AIAssistant
    @ObservedObject private var usageStore = AIUsageStore.shared
    @State private var isExpanded: Bool = false
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @State private var chatInput: String = ""
    @FocusState private var isChatInputFocused: Bool
    @State private var showingPrivacySettings: Bool = false
    @State private var includeHistoryContext: Bool = true
    @State private var showingClearConfirmation: Bool = false
    // Agent UI mode: false = Ask (chat), true = Agent (act)
    @State private var agentMode: Bool = false

    // OPTIMIZATION: Fix initialization spinner animation
    @State private var initSpinnerRotation: Double = 0
    @State private var isSpinnerAnimating: Bool = false  // FIXED: Track animation state to prevent conflicts

    // REMOVED: Old typing indicator state - now using unified AIAnimationState from AIAssistant

    // Configuration
    private let collapsedWidth: CGFloat = 4
    private let expandedWidth: CGFloat = 320
    private let maxExpandedWidth: CGFloat = 480

    // Initializer
    init(tabManager: TabManager) {
        self.tabManager = tabManager
        self._aiAssistant = StateObject(wrappedValue: AIAssistant.shared)
    }

    // MARK: - Agent Timeline Area
    @ViewBuilder
    private func agentTimelineArea() -> some View {
        ScrollViewReader { _ in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !aiAssistant.isInitialized {
                        aiInitializationView()
                    } else if let run = aiAssistant.currentAgentRun {
                        // Render the user's instruction using the same user-bubble style as Ask mode
                        ChatBubbleView(
                            message: ConversationMessage(
                                role: .user,
                                content: run.title,
                                timestamp: run.startedAt
                            )
                        )
                        .padding(.bottom, 4)

                        ForEach(Array(run.steps.enumerated()), id: \.1.id) { index, step in
                            AgentTimelineRow(index: index + 1, step: step)
                        }
                        if let finishedAt = run.finishedAt {
                            Text(
                                "Finished \(finishedAt.formatted(date: .omitted, time: .shortened))"
                            )
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        }
                    } else {
                        agentReadyPlaceholder()
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Agent send
    private func sendAgent() {
        let message = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        // Immediate processing state for Agent mode
        aiAssistant.animationState = .processing
        chatInput = ""
        // Support dev slash-commands in Agent mode as well
        if message.hasPrefix("/tool ") || message.hasPrefix("/plan ") {
            handleAgentCommand(message)
            return
        }
        Task {
            // Prefer new iterative loop for page-agnostic multi-step behavior
            await aiAssistant.runAgentLoop(message)
            await MainActor.run { aiAssistant.animationState = .idle }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main sidebar content
            sidebarContent()
                .frame(width: isExpanded ? expandedWidth : collapsedWidth)
                .background(sidebarBackground())
                .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 12 : 0))
                .overlay(
                    // Right edge activation zone when collapsed
                    rightEdgeActivationZone()
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
                .onReceive(NotificationCenter.default.publisher(for: .toggleAISidebar)) { _ in
                    toggleSidebar()
                }
                .onReceive(NotificationCenter.default.publisher(for: .focusAIInput)) { _ in
                    expandAndFocusInput()
                }
                .onReceive(NotificationCenter.default.publisher(for: .pageNavigationCompleted)) {
                    _ in
                    // Trigger context status update when any page navigation completes
                    // The @ObservedObject tabManager will automatically refresh the context status view
                }
                .sheet(isPresented: $showingPrivacySettings) {
                    AIPrivacySettings()
                }
                .onAppear {
                    // Show AI sidebar on first app launch - FIXED: Use animation to prevent bouncing
                    if !hasLaunchedBefore {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            isExpanded = true
                        }
                        hasLaunchedBefore = true
                        NSLog("🎉 First app launch - showing AI sidebar by default")
                    }

                    // Initialize AI system on first appearance - delayed to prevent race conditions
                    Task {
                        // FIXED: Small delay to let UI settle before starting AI initialization
                        try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
                        await aiAssistant.initialize()
                    }
                }
        }
    }

    // MARK: - Sidebar Content

    @ViewBuilder
    private func sidebarContent() -> some View {
        if isExpanded {
            expandedSidebarView()
        } else {
            collapsedSidebarView()
        }
    }

    @ViewBuilder
    private func collapsedSidebarView() -> some View {
        // Completely invisible collapsed state - only hover zone remains active
        Rectangle()
            .fill(Color.clear)
            .frame(width: collapsedWidth)
    }

    @ViewBuilder
    private func expandedSidebarView() -> some View {
        VStack(spacing: 0) {
            // Header with AI status
            sidebarHeader()

            // TL;DR Component – progressive disclosure (absorbs page context)
            TLDRCard(tabManager: tabManager, aiAssistant: aiAssistant)
                .padding(.bottom, 4)
                .id("tldr-card")

            Divider()
                .opacity(0.3)

            // Content
            if agentMode {
                ZStack {
                    agentTimelineArea()
                    if aiAssistant.animationState == .processing {
                        processingOverlay()
                    }
                }
            } else {
                chatMessagesArea()
            }

            // Input area
            chatInputArea()

            // Usage meter intentionally hidden for a cleaner minimal UI
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Header

    @ViewBuilder
    private func contextStatusView() -> some View {
        // Reactive check based on active tab - this will re-evaluate when tabManager.activeTab changes
        let canExtractContext =
            tabManager.activeTab != nil && contextManager.canExtractContext(from: tabManager)

        if canExtractContext {
            HStack(spacing: 6) {
                // Context available indicator
                Image(
                    systemName: contextManager.isExtracting
                        ? "doc.text.magnifyingglass" : "doc.text"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(contextManager.isExtracting ? .blue : .green)

                Text(contextManager.isExtracting ? "Reading page..." : "Page context")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Show word count only if context is from the current active tab
                if let context = contextManager.lastExtractedContext,
                    let activeTabId = tabManager.activeTab?.id,
                    context.tabId == activeTabId
                {
                    Text("\(context.wordCount)w")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial.opacity(0.5))
            )
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
            .id(
                "\(tabManager.activeTab?.id.uuidString ?? "none")-\(tabManager.activeTab?.url?.absoluteString ?? "none")"
            )
        }
    }

    @ViewBuilder
    private func sidebarHeader() -> some View {
        HStack {
            // AI status indicator
            AIStatusIndicator(
                isInitialized: aiAssistant.isInitialized,
                isProcessing: aiAssistant.isProcessing,
                status: aiAssistant.initializationStatus
            )

            Spacer()

            // Provider / Model quick chip (progressive disclosure)
            if let provider = providerManager.currentProvider {
                Menu {
                    // Provider switcher
                    Section("Providers") {
                        ForEach(providerManager.availableProviders, id: \.providerId) {
                            p in
                            Button(action: {
                                Task { try? await providerManager.switchProvider(to: p) }
                            }) {
                                Label(
                                    p.displayName,
                                    systemImage: p.providerType == .local ? "lock.fill" : "network")
                            }
                        }
                    }
                    // Model picker for current provider
                    if !provider.availableModels.isEmpty {
                        Section("Model") {
                            ForEach(provider.availableModels, id: \.id) { m in
                                Button(action: {
                                    providerManager.updateSelectedModel(m)
                                }) {
                                    let isSelected = m.id == provider.selectedModel?.id
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.name)
                                            if let pricing = m.pricing {
                                                let inUSD = pricing.inputPerMTokensUSD ?? 0
                                                let outUSD = pricing.outputPerMTokensUSD ?? 0
                                                Text(
                                                    String(
                                                        format: "$%.2f /1M in, $%.2f /1M out",
                                                        inUSD, outUSD)
                                                ).font(.caption).foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if isSelected { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }
                    }
                    // Inline privacy toggle placeholder (context sharing)
                    Section("Privacy") {
                        // The actual toggle is managed in settings; this is a quick link
                        Button("Privacy Settings…") {
                            showingPrivacySettings = true
                        }
                    }
                } label: {
                    // Icon-only to reduce truncation in header
                    HStack(spacing: 4) {
                        Image(systemName: provider.providerType == .local ? "lock.shield" : "cloud")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(
                    "Switch provider/model\nSelected: \(provider.selectedModel?.name ?? provider.displayName)"
                )
            }

            // Clear conversation button - only show when messages exist
            if !aiAssistant.messages.isEmpty {
                Button(action: {
                    showingClearConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(0.7)
                .help("Clear conversation")
                .confirmationDialog(
                    "Clear Conversation",
                    isPresented: $showingClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear", role: .destructive) {
                        clearConversation()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete all messages in this conversation.")
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.8),
                    value: aiAssistant.messages.isEmpty)
            }

            // Collapse button
            Button(action: {
                collapseSidebar()
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(0.7)
        }
        .frame(height: 36)
        .padding(.bottom, 8)
    }

    // MARK: - Chat Messages Area

    @ViewBuilder
    private func chatMessagesArea() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !aiAssistant.isInitialized {
                        // Initialization status - FIXED: Removed conflicting transition animation
                        aiInitializationView()
                            .transition(.opacity)
                    } else if aiAssistant.messages.isEmpty {
                        // Show placeholder when no messages - FIXED: Removed conflicting transition animation
                        chatMessagesPlaceholder()
                            .transition(.opacity)
                    } else {
                        // Display actual chat messages with unified streaming support
                        ForEach(aiAssistant.messages) { message in
                            ChatBubbleView(
                                message: message,
                                isStreaming: aiAssistant.animationState.streamingMessageId
                                    == message.id,
                                streamingText: aiAssistant.animationState.streamingMessageId
                                    == message.id ? aiAssistant.streamingText : ""
                            )
                            .id(message.id)
                        }

                        // Show unified typing indicator when AI is in typing state
                        if aiAssistant.animationState == .typing {
                            unifiedTypingIndicatorView()
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .onReceive(aiAssistant.$isProcessing) { _ in
                // Auto-scroll to bottom when new messages arrive
                if let lastMessage = aiAssistant.messages.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func aiInitializationView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Modern loading header
            HStack(spacing: 12) {
                ZStack {
                    if aiAssistant.isInitialized {
                        // Success state
                        Circle()
                            .fill(.green.opacity(0.1))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.green)
                            )
                    } else {
                        // Loading state with subtle animation
                        Circle()
                            .fill(.blue.opacity(0.08))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .trim(from: 0, to: 0.7)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.blue.opacity(0.8), .blue.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(initSpinnerRotation))
                                    .onAppear {
                                        // FIXED: Start animation only once to prevent conflicts
                                        if !aiAssistant.isInitialized && !isSpinnerAnimating {
                                            isSpinnerAnimating = true
                                            withAnimation(
                                                .linear(duration: 1.5).repeatForever(
                                                    autoreverses: false)
                                            ) {
                                                initSpinnerRotation = 360
                                            }
                                        }
                                    }
                                    .onChange(of: aiAssistant.isInitialized) { _, isInitialized in
                                        if !isInitialized && !isSpinnerAnimating {
                                            // FIXED: Only start if not already animating to prevent loop conflicts
                                            isSpinnerAnimating = true
                                            withAnimation(
                                                .linear(duration: 1.5).repeatForever(
                                                    autoreverses: false)
                                            ) {
                                                initSpinnerRotation = 360
                                            }
                                        } else if isInitialized && isSpinnerAnimating {
                                            // FIXED: Stop animation cleanly and reset state
                                            isSpinnerAnimating = false
                                            withAnimation(.easeOut(duration: 0.3)) {
                                                initSpinnerRotation = 0
                                            }
                                        }
                                    }
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(aiAssistant.isInitialized ? "AI Ready" : "Preparing AI")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(aiAssistant.initializationStatus)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }

            // Progress indicator for non-initialized state
            if !aiAssistant.isInitialized {
                VStack(spacing: 8) {
                    // Subtle progress bar
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(.blue.opacity(progressDotOpacity(for: index)))
                                .frame(width: 24, height: 2)
                                // FIXED: Stable opacity animation without continuous time-based updates
                                .opacity(aiAssistant.isInitialized ? 0.3 : 1.0)
                                .animation(
                                    .easeInOut(duration: 0.8)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.2),
                                    value: aiAssistant.isInitialized
                                )
                        }
                    }

                    Text("Downloading and optimizing model...")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            if let error = aiAssistant.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)

                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)  // FIXED: Consistent frame configuration
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.quaternary, lineWidth: 0.5)
                )
        )
    }

    // FIXED: Removed time-based calculation that caused continuous UI updates
    private func progressDotOpacity(for index: Int) -> Double {
        // Use a stable opacity pattern instead of time-based animation
        let baseOpacities = [0.8, 0.6, 0.4, 0.3]
        return baseOpacities[index % baseOpacities.count]
    }

    @ViewBuilder
    private func chatMessagesPlaceholder() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)

            let providerBadge: String = {
                if let p = providerManager.currentProvider {
                    return p.providerType == .local ? "Local" : p.displayName
                } else {
                    return "Local"
                }
            }()

            Text("AI Ready · \(providerBadge)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.quaternary, lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func agentReadyPlaceholder() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)

            let providerBadge: String = {
                if let p = providerManager.currentProvider {
                    return p.providerType == .local ? "Local" : p.displayName
                } else {
                    return "Local"
                }
            }()

            Text("Agent Ready · \(providerBadge)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.quaternary, lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func suggestionRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 12)

            Text(text)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Unified Typing Indicator

    @ViewBuilder
    private func unifiedTypingIndicatorView() -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Unified typing indicator bubble with LoadingDotsView - no avatar for consistency
            LoadingDotsView(dotColor: .secondary.opacity(0.6), dotSize: 6, spacing: 4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                        .opacity(0.9)
                )

            Spacer(minLength: 24)  // Reduced from 32 to match message bubbles
        }
        .padding(.horizontal, 4)  // Reduced from 8 for consistency with message bubbles
        .padding(.vertical, 2)
    }

    // MARK: - Processing Overlay (Agent Mode)
    @ViewBuilder
    private func processingOverlay() -> some View {
        VStack(spacing: 12) {
            // Raycast/Linear inspired subtle pulse
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Circle()
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .trim(from: 0, to: 0.65)
                            .stroke(
                                Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                            .rotationEffect(.degrees(initSpinnerRotation))
                            .onAppear {
                                withAnimation(
                                    .linear(duration: 1.4).repeatForever(autoreverses: false)
                                ) {
                                    initSpinnerRotation = 360
                                }
                            }
                    )
            }
            Text("Planning actions…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    // MARK: - Chat Input Area

    @ViewBuilder
    private func chatInputArea() -> some View {
        VStack(spacing: 8) {
            // Context controls + compact mode toggle
            HStack(spacing: 8) {
                // History context toggle
                HStack(spacing: 4) {
                    Button(action: {
                        includeHistoryContext.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: includeHistoryContext ? "clock.fill" : "clock")
                                .font(.system(size: 12))
                            Text("History")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(includeHistoryContext ? .accentColor : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Include browsing history in AI context")
                }

                Spacer()

                // Minimal Ask/Agent pill
                AgentModeTogglePill(isAgent: $agentMode)

                // Privacy settings button
                Button(action: {
                    showingPrivacySettings = true
                }) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Privacy settings")
            }
            .padding(.horizontal, 4)
            .opacity(0.8)

            // Input field row
            HStack(spacing: 8) {
                TextField(
                    agentMode ? "Ask the agent to act..." : "Ask about this page...",
                    text: $chatInput, axis: .vertical
                )
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .opacity(0.6)
                )
                .focused($isChatInputFocused)
                .onSubmit {
                    if agentMode { sendAgent() } else { sendMessage() }
                }
                .disabled(!aiAssistant.isInitialized)
                .onChange(of: isChatInputFocused) { _, _ in }
                .onChange(of: aiAssistant.isInitialized) { _, _ in }

                // Send button
                Button(action: {
                    if agentMode { sendAgent() } else { sendMessage() }
                }) {
                    Image(
                        systemName: aiAssistant.isProcessing
                            ? "stop.circle" : "arrow.up.circle.fill"
                    )
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(chatInput.isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(chatInput.isEmpty || !aiAssistant.isInitialized)
            }
        }
        .frame(minHeight: 44)
        .padding(.top, 12)
    }

    // MARK: - Live Usage Micro-Meter
    @ViewBuilder
    private func usageMicroMeter() -> some View {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let todayTotals = usageStore.aggregate(in: startOfDay...now)
        let byProvider = Dictionary(grouping: todayTotals, by: { $0.providerId })
        let currentProviderId = AIProviderManager.shared.currentProvider?.providerId
        let totalsForProvider: (tokens: Int, cost: Double)? = currentProviderId.flatMap { pid in
            guard let rows = byProvider[pid], !rows.isEmpty else { return nil }
            let sumTokens = rows.reduce(0) { $0 + $1.totalTokens }
            let sumCost = rows.reduce(0.0) { $0 + $1.estimatedCostUSD }
            return (sumTokens, sumCost)
        }

        HStack(spacing: 8) {
            Image(systemName: "gauge")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if let t = totalsForProvider {
                Text("Today: \(t.tokens) tok")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                if t.cost > 0 {
                    Text("$\(String(format: "%.3f", t.cost))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Today: 0 tok")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Quick link to Usage & Billing
            Button(action: { NotificationCenter.default.post(name: .openUsageBilling, object: nil) }
            ) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Open Usage & Billing")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .opacity(0.6)
        )
        .padding(.top, 6)
    }

    // MARK: - Background Styling

    @ViewBuilder
    private func sidebarBackground() -> some View {
        if isExpanded {
            ZStack {
                // Base glass material
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.8)

                // Subtle gradient overlay
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.02),
                                Color.accentColor.opacity(0.01),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Inner glow
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        } else {
            // Completely transparent background when collapsed
            Color.clear
        }
    }

    // MARK: - Right Edge Activation Zone

    @ViewBuilder
    private func rightEdgeActivationZone() -> some View {
        if !isExpanded {
            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20)  // 20pt hover zone
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Interaction Methods

    private func toggleSidebar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded.toggle()
        }

        // Broadcast state change for button synchronization
        NotificationCenter.default.post(name: .aISidebarStateChanged, object: isExpanded)

        if isExpanded {
            // Focus input after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isChatInputFocused = true
            }
        } else {
            isChatInputFocused = false
        }
    }

    private func expandSidebar() {
        guard !isExpanded else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded = true
        }

        // Broadcast state change for button synchronization
        NotificationCenter.default.post(name: .aISidebarStateChanged, object: true)

        // Focus input after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isChatInputFocused = true
        }
    }

    private func collapseSidebar() {
        guard isExpanded else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded = false
        }

        // Broadcast state change for button synchronization
        NotificationCenter.default.post(name: .aISidebarStateChanged, object: false)

        isChatInputFocused = false
    }

    private func expandAndFocusInput() {
        expandSidebar()
    }

    private func sendMessage() {
        guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let message = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        chatInput = ""

        // DEV: Minimal agent command shim
        // Usage:
        //   /tool click {"locator": {"text": "Sign in"}}
        //   /tool typeText {"locator": {"name": "email"}, "text": "test@example.com"}
        //   /plan [{"type":"scroll","direction":"down","amountPx":600}]
        if message.hasPrefix("/tool ") || message.hasPrefix("/plan ") {
            handleAgentCommand(message)
            return
        }

        // Set typing state immediately using unified animation system
        aiAssistant.animationState = .typing

        // Process message with AI Assistant using streaming for ChatGPT-like experience
        Task {
            do {
                // Start streaming response with history context option
                let stream = aiAssistant.processStreamingQuery(
                    message, includeContext: true, includeHistory: includeHistoryContext)

                // Process streaming response - AIAssistant now manages state transitions automatically
                var fullResponse = ""
                for try await chunk in stream {
                    fullResponse += chunk
                    if AppLog.isVerboseEnabled {
                        AppLog.debug("Streaming token (total=\(fullResponse.count))")
                    }
                }

                if AppLog.isVerboseEnabled {
                    AppLog.debug("Streaming completed: len=\(fullResponse.count)")
                }

            } catch {
                AppLog.error("Sidebar streaming failed: \(error.localizedDescription)")

                // Clear animation state on error (AIAssistant handles this but ensure cleanup)
                await MainActor.run {
                    if aiAssistant.animationState == .typing {
                        aiAssistant.animationState = .idle
                    }
                }

                if AppLog.isVerboseEnabled {
                    AppLog.debug("Streaming error handled - cleanup done")
                }
            }
        }
    }

    // MARK: - Minimal Agent Command Handler (dev-only)
    private func handleAgentCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/tool ") {
            // Format: /tool <name> <json>
            let rest = trimmed.dropFirst(6)
            let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { return }
            let name = String(parts[0])
            let json = String(parts[1])
            guard let data = json.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                NSLog("❌ /tool args JSON parse failed")
                return
            }
            Task {
                let result = await aiAssistant.callAgentTool(name: name, arguments: obj)
                NSLog(
                    "🛠️ Tool result: name=\(result.name) ok=\(result.ok) message=\(result.message ?? "nil") dataKeys=\(result.data?.keys.map{ $0 } ?? [])"
                )
            }
            return
        }
        if trimmed.hasPrefix("/plan ") {
            // Format: /plan <jsonArray of PageAction>
            let json = String(trimmed.dropFirst(6))
            guard let data = json.data(using: .utf8) else { return }
            do {
                let plan = try JSONDecoder().decode([PageAction].self, from: data)
                Task { _ = await aiAssistant.runAgentPlan(plan) }
            } catch {
                NSLog("❌ /plan JSON decode failed: \(error)")
            }
            return
        }
    }

    private func clearConversation() {
        withAnimation(.easeInOut(duration: 0.3)) {
            aiAssistant.clearConversation()
        }
        AppLog.debug("Conversation cleared via UI")
    }

}

// MARK: - AI Status Indicator Component

struct AIStatusIndicator: View {
    let isInitialized: Bool
    let isProcessing: Bool
    let status: String

    // OPTIMIZATION: Fix spinner animation with proper state management
    @State private var rotationAngle: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            // Modern status indicator
            ZStack {
                // Background circle
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 20, height: 20)

                // Status dot or processing indicator
                if isProcessing {
                    // FIXED: Elegant processing animation with proper state binding
                    Circle()
                        .trim(from: 0, to: 0.6)
                        .stroke(
                            AngularGradient(
                                colors: [statusColor.opacity(0.3), statusColor],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(rotationAngle))
                        .onAppear {
                            // Start continuous rotation when processing begins - using standard 1.5s timing
                            if isProcessing {
                                withAnimation(
                                    .linear(duration: 1.5).repeatForever(autoreverses: false)
                                ) {
                                    rotationAngle = 360
                                }
                            }
                        }
                        .onChange(of: isProcessing) { _, newValue in
                            if newValue {
                                // Start spinning when processing begins - consistent 1.5s timing
                                withAnimation(
                                    .linear(duration: 1.5).repeatForever(autoreverses: false)
                                ) {
                                    rotationAngle = 360
                                }
                            } else {
                                // Stop spinning when processing ends - quick 0.3s cleanup
                                withAnimation(.easeOut(duration: 0.3)) {
                                    rotationAngle = 0
                                }
                            }
                        }
                } else {
                    // Solid status dot
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [statusColor, statusColor.opacity(0.8)],
                                center: .topLeading,
                                startRadius: 2,
                                endRadius: 8
                            )
                        )
                        .frame(width: 8, height: 8)
                        .scaleEffect(isInitialized ? 1.0 : 0.8)
                        .animation(.easeInOut(duration: 0.3), value: isInitialized)
                }

                // Pulse effect for ready state
                if isInitialized && !isProcessing {
                    Circle()
                        .stroke(statusColor.opacity(0.4), lineWidth: 1)
                        .frame(width: 16, height: 16)
                        .scaleEffect(1.2)
                        .opacity(0)
                        .animation(
                            .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                            value: isInitialized
                        )
                        .onAppear {
                            withAnimation {
                                // Trigger pulse animation
                            }
                        }
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                // Primary status
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                // Secondary status
                if !status.isEmpty && status != statusText {
                    Text(status)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var statusText: String {
        if isProcessing {
            return "Thinking..."  // OPTIMIZATION: Better user feedback
        } else if isInitialized {
            return "AI Ready"
        } else {
            return "Starting"
        }
    }

    private var statusColor: Color {
        if isProcessing {
            return .blue
        } else if isInitialized {
            return .green
        } else {
            return .orange
        }
    }
}

// MARK: - Notification Extensions
// Note: AI Assistant notification names are defined in WebApp.swift

// MARK: - Preview

#Preview {
    HStack {
        Rectangle()
            .fill(.gray.opacity(0.3))
            .frame(maxWidth: .infinity)

        AISidebar(tabManager: TabManager())
    }
    .frame(width: 800, height: 600)
}
