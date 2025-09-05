import Combine
import SwiftUI

/// Next-generation TL;DR component with progressive disclosure
/// Auto-generates summaries of current page content with subtle, minimal UI
struct TLDRCard: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var aiAssistant: AIAssistant
    @ObservedObject private var contextManager = ContextManager.shared

    @State private var isExpanded: Bool = false
    @State private var tldrSummary: String = ""
    @State private var sentimentEmoji: String = ""
    @State private var isGenerating: Bool = false
    @State private var lastProcessedURL: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isCancelled: Bool = false

    // Streaming state for real-time TL;DR generation
    @State private var isStreaming: Bool = false
    @State private var streamingText: String = ""

    // Animation states
    @State private var pulseOpacity: Double = 0.3
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedView()
            } else {
                collapsedView()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .background(cardBackground())
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 12 : 20))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 12 : 20)
                .stroke(.quaternary.opacity(0.3), lineWidth: 0.5)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .onReceive(NotificationCenter.default.publisher(for: .pageNavigationCompleted)) { _ in
            autoGenerateTLDR()
        }
        .onReceive(contextManager.$lastExtractedContext) { _ in
            autoGenerateTLDR()
        }
        .onChange(of: tabManager.activeTab?.url?.absoluteString) { _, newURL in
            if newURL != lastProcessedURL {
                autoGenerateTLDR()
            }
        }
        .onAppear {
            startPulseAnimation()
            autoGenerateTLDR()
        }
        .onChange(of: isGenerating) { _, newValue in
            if newValue {
                startSpinnerAnimation()
            } else {
                stopSpinnerAnimation()
            }
        }
        .onReceive(aiAssistant.$isProcessing) { isProcessing in
            // If AI starts processing (chat), cancel any running TL;DR
            if isProcessing && isGenerating {
                cancelTLDRIfGenerating()
            }
        }
    }

    // MARK: - Collapsed View

    @ViewBuilder
    private func collapsedView() -> some View {
        HStack(spacing: 6) {
            // Sentiment emoji (prominent display) or status indicator
            if !sentimentEmoji.isEmpty && !isGenerating {
                Text(sentimentEmoji)
                    .font(.system(size: 14))
                    .opacity(pulseOpacity)
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                        value: pulseOpacity
                    )
            } else {
                // Fallback status indicator when no emoji or generating
                ZStack {
                    Circle()
                        .fill(statusGradient)
                        .frame(width: 16, height: 16)

                    if isGenerating {
                        // Subtle loading animation
                        Circle()
                            .trim(from: 0, to: 0.6)
                            .stroke(
                                AngularGradient(
                                    colors: [.blue.opacity(0.3), .blue],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                            )
                            .frame(width: 14, height: 14)
                            .rotationEffect(.degrees(shimmerOffset))
                            .onAppear {
                                withAnimation(
                                    .linear(duration: 1.2).repeatForever(autoreverses: false)
                                ) {
                                    shimmerOffset = 360
                                }
                            }
                            .onDisappear {
                                shimmerOffset = 0
                            }
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }

            // TL;DR label
            Text("TL;DR")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary.opacity(0.8))

            // AI Busy indicator if processing chat
            if aiAssistant.isProcessing && !isGenerating {
                Text("AI Busy")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.orange.opacity(0.8))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.orange.opacity(0.1))
                    )
            }

            Spacer()

            // Expand hint
            Image(systemName: "chevron.up")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .disabled(isGenerating && tldrSummary.isEmpty)
    }

    // MARK: - Expanded View

    @ViewBuilder
    private func expandedView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with collapse button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)

                    Text("TL;DR")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Content area
            if isGenerating && tldrSummary.isEmpty && !isStreaming {
                generatingView()
            } else if showError {
                errorView()
            } else if tldrSummary.isEmpty && !isStreaming {
                emptyStateView()
            } else {
                summaryView()
            }
        }
        .padding(12)
    }

    // MARK: - Content Views

    @ViewBuilder
    private func generatingView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Subtle shimmer placeholder
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .secondary.opacity(0.1),
                                    .secondary.opacity(0.3),
                                    .secondary.opacity(0.1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 12)
                        .frame(width: index == 2 ? 80 : nil)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .offset(x: shimmerOffset)
                        .clipped()
                }
            }

            Text("Analyzing page content...")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }

    @ViewBuilder
    private func errorView() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)

            Text("Unable to generate summary")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Button("Retry") {
                autoGenerateTLDR()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.blue)
            .buttonStyle(PlainButtonStyle())
        }
    }

    @ViewBuilder
    private func emptyStateView() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))

            Text("No content to summarize")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.8))
        }
    }

    @ViewBuilder
    private func summaryView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sentiment chip if available
            if !sentimentEmoji.isEmpty {
                HStack(spacing: 4) {
                    Text("Sentiment:")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))

                    Text(sentimentEmoji)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary.opacity(0.3))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Render TLDR summary with markdown support (streaming or final)
            Group {
                // Use streaming text if currently streaming, otherwise use final summary
                let displayText = isStreaming ? streamingText : tldrSummary

                // Preprocess to fix missing spaces that break markdown
                let processedSummary =
                    displayText
                    .replacingOccurrences(
                        of: "(?<=[.!?:])(?=[A-Z])", with: " ", options: .regularExpression
                    )
                    // Insert a line-break before list markers that directly follow a colon ("We can:*" → "We can:\n* ")
                    .replacingOccurrences(
                        of: "(?<=:)\\s*\\*", with: "\n* ", options: .regularExpression)

                // Only parse markdown for final text to avoid crashes with incomplete syntax during streaming
                if isStreaming {
                    Text(processedSummary)
                } else if let attributedString = try? AttributedString(
                    markdown: processedSummary,
                    options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace))
                {
                    Text(attributedString)
                } else {
                    // Fallback to plain text if markdown parsing fails
                    Text(processedSummary)
                }
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(.primary.opacity(0.9))
            // Allow the full summary to be visible when expanded
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(
                // Streaming indicator like chat messages
                streamingIndicator(),
                alignment: .bottomTrailing
            )

            // Word count indicator (show for streaming text or final summary)
            if !tldrSummary.isEmpty || isStreaming {
                let displayText = isStreaming ? streamingText : tldrSummary
                if !displayText.isEmpty {
                    HStack {
                        Text("\(displayText.split(separator: " ").count) words")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))

                        if isStreaming {
                            Text("• streaming")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.blue.opacity(0.8))
                        }

                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Streaming Indicator

    @ViewBuilder
    private func streamingIndicator() -> some View {
        if isStreaming {
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    LoadingDotsView(dotColor: .blue.opacity(0.6), dotSize: 3, spacing: 2)
                        .padding(.trailing, 4)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Background Styling

    @ViewBuilder
    private func cardBackground() -> some View {
        ZStack {
            // Base glass material
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isExpanded ? 0.8 : 0.6)

            // Subtle gradient overlay
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.02),
                            Color.blue.opacity(0.01),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    // MARK: - Computed Properties

    private var statusIcon: String {
        if showError {
            return "exclamationmark"
        } else if tldrSummary.isEmpty {
            return "doc.text"
        } else {
            return "checkmark"
        }
    }

    private var statusGradient: LinearGradient {
        if showError {
            return LinearGradient(
                colors: [.orange.opacity(0.8), .orange.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if tldrSummary.isEmpty {
            return LinearGradient(
                colors: [.secondary.opacity(0.6), .secondary.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [.green.opacity(0.8), .green.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Auto-Generation Logic

    private func autoGenerateTLDR() {
        guard let activeTab = tabManager.activeTab,
            let currentURL = activeTab.url?.absoluteString,
            currentURL != lastProcessedURL,
            !currentURL.isEmpty,
            aiAssistant.isInitialized
        else {
            return
        }

        // CONCURRENCY CHECK: Don't start if AI is already busy with chat
        if aiAssistant.isProcessing {
            NSLog("⚠️ TL;DR: Skipping generation - AI is busy with chat")
            return
        }

        // Reset state for new page
        showError = false
        errorMessage = ""
        tldrSummary = ""
        sentimentEmoji = ""
        isCancelled = false
        lastProcessedURL = currentURL
        isGenerating = true
        isStreaming = false
        streamingText = ""

        NSLog("🔄 TL;DR: Auto-generating with streaming for \(currentURL)")

        Task {
            do {
                // Small delay to ensure context is extracted after page load
                try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds for page content to be fully extracted

                // Check if cancelled or AI became busy during delay
                if await MainActor.run(body: { isCancelled }) || aiAssistant.isProcessing {
                    await MainActor.run {
                        isGenerating = false
                        isStreaming = false
                        NSLog("⚠️ TL;DR: Generation cancelled - AI became busy or was cancelled")
                    }
                    return
                }

                // Start streaming generation
                await MainActor.run {
                    isStreaming = true
                    isGenerating = false  // Switch from loading to streaming
                }

                // Generate TL;DR using the new streaming method
                let stream = aiAssistant.generatePageTLDRStreaming()

                var accumulatedResponse = ""

                // Process streaming response
                for try await chunk in stream {
                    accumulatedResponse += chunk

                    await MainActor.run {
                        streamingText = accumulatedResponse
                    }
                }

                // Parse final response and update UI
                let (emoji, summary) = parseTLDRResponse(accumulatedResponse)

                await MainActor.run {
                    isStreaming = false
                    isGenerating = false
                    sentimentEmoji = emoji
                    tldrSummary = summary
                    streamingText = ""
                    showError = false

                    if AppLog.isVerboseEnabled {
                        AppLog.debug("TL;DR streaming done: emoji=\(emoji) len=\(summary.count)")
                    }
                }

            } catch {
                await MainActor.run {
                    isGenerating = false
                    isStreaming = false
                    streamingText = ""
                    showError = true
                    errorMessage = error.localizedDescription

                    AppLog.error("TL;DR streaming failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Parse emoji and summary from AI response
    private func parseTLDRResponse(_ response: String) -> (emoji: String, summary: String) {
        let lines = response.split(separator: "\n", omittingEmptySubsequences: true)

        // Look for emoji in first line or extract from response
        var emoji = ""
        var summary = response

        // Try to extract emoji from first line
        if let firstLine = lines.first {
            let firstLineStr = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
            // Check if first line contains an emoji (common sentiment emojis)
            let sentimentEmojis = [
                "📰", "🔬", "💼", "🎬", "⚠️", "😊", "😐", "😟", "🏠", "🛒", "🎮", "🎵", "🍔", "✈️", "⚽", "🎨", "📊",
                "💡",
            ]

            for sentimentEmoji in sentimentEmojis {
                if firstLineStr.contains(sentimentEmoji) {
                    emoji = sentimentEmoji
                    // Remove emoji from summary
                    summary = response.replacingOccurrences(of: sentimentEmoji, with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        // If no emoji found, default based on content keywords
        if emoji.isEmpty {
            let lowercasedResponse = response.lowercased()
            if lowercasedResponse.contains("news") || lowercasedResponse.contains("breaking") {
                emoji = "📰"
            } else if lowercasedResponse.contains("tech") || lowercasedResponse.contains("software")
            {
                emoji = "🔬"
            } else if lowercasedResponse.contains("business")
                || lowercasedResponse.contains("finance")
            {
                emoji = "💼"
            } else {
                emoji = "😐"  // Default neutral
            }
        }

        return (emoji: emoji, summary: summary)
    }

    /// Cancel TL;DR generation if user starts interacting with chat
    func cancelTLDRIfGenerating() {
        if isGenerating || isStreaming {
            isCancelled = true
            isGenerating = false
            isStreaming = false
            streamingText = ""
            NSLog("🚫 TL;DR: Generation cancelled due to user interaction")
        }
    }

    // MARK: - Animation Helpers

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.8
        }
    }

    private func startSpinnerAnimation() {
        shimmerOffset = 0
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            shimmerOffset = 360
        }
    }

    private func stopSpinnerAnimation() {
        shimmerOffset = 0
    }
}

// MARK: - Preview

#Preview {
    VStack {
        TLDRCard(
            tabManager: TabManager(),
            aiAssistant: AIAssistant.shared
        )
        .frame(width: 300)

        Spacer()
    }
    .padding()
    .background(.regularMaterial)
}
