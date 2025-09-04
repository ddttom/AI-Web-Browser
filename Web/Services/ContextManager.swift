import CoreData
import Foundation
import SwiftUI
import WebKit

/// Manages webpage content extraction and context generation for AI integration
/// Provides cleaned, summarized webpage content to enhance AI responses
@MainActor
class ContextManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isExtracting: Bool = false
    @Published var lastExtractedContext: WebpageContext?
    @Published var contextStatus: String = "Ready"

    // MARK: - Singleton

    static let shared = ContextManager()

    // MARK: - Properties

    /// Maximum number of characters allowed in `WebpageContext.text`.
    /// 0 ➜ unlimited (no truncation). We default to **0** because modern Apple-Silicon devices can easily feed tens of thousands of characters to the 2B Gemma model.
    /// If we later decide to cap it dynamically, we just need to set this to a non-zero value.
    private let maxContentLength: Int = 0
    private let contentExtractionTimeout = 10.0  // seconds
    private var lastExtractionTime: Date?
    private let minExtractionInterval: TimeInterval = 2.0  // Prevent spam extraction

    // ENHANCED: Content extraction caching
    private var contextCache: [String: CachedContext] = [:]
    private let maxCacheSize = 50  // Maximum number of cached contexts
    private let cacheExpirationTime: TimeInterval = 300  // 5 minutes
    private var cacheAccessOrder: [String] = []  // For LRU eviction

    // HISTORY CONTEXT CONFIGURATION
    private let maxHistoryItems = 10  // Limit history items for context
    private let maxHistoryDays: TimeInterval = 1 * 24 * 60 * 60  // 1 day lookback
    private let maxHistoryContentLength = 3000  // Limit history context size

    // Privacy settings for history context
    @Published var isHistoryContextEnabled: Bool = true
    @Published var historyContextScope: HistoryContextScope = .recent

    private init() {
        AppLog.debug("ContextManager initialized")
    }

    // MARK: - Public Interface

    /// Extract context from the currently active tab
    func extractCurrentPageContext(from tabManager: TabManager) async -> WebpageContext? {
        guard let activeTab = tabManager.activeTab,
            let webView = activeTab.webView
        else {
            if AppLog.isVerboseEnabled {
                AppLog.debug("No active tab/WebView for context extraction")
            }
            return nil
        }

        // Only throttle if we have *already* extracted context for the *same* page very recently.
        // This prevents scenarios where the user quickly navigates to a new URL but the previous
        // page's context is still returned because the interval has not expired (e.g. navigating
        // from a weather page to a social media post within two seconds). [[Fixes stale-context bug]]
        if let lastTime = lastExtractionTime,
            Date().timeIntervalSince(lastTime) < minExtractionInterval,
            let lastContext = lastExtractedContext
        {
            let currentURL = webView.url?.absoluteString
            if lastContext.url == currentURL {
                return lastContext
            }
        }

        return await extractPageContext(from: webView, tab: activeTab)
    }

    /// Extract context from specific WebView with intelligent caching
    func extractPageContext(from webView: WKWebView, tab: Tab) async -> WebpageContext? {
        guard let url = webView.url?.absoluteString else {
            if AppLog.isVerboseEnabled { AppLog.debug("No URL for context extraction") }
            return nil
        }

        // Check cache first
        if let cachedContext = getCachedContext(for: url) {
            if AppLog.isVerboseEnabled {
                AppLog.debug(
                    "Using cached context: len=\(cachedContext.context.text.count) title=\(cachedContext.context.title)"
                )
            }

            await MainActor.run {
                lastExtractedContext = cachedContext.context
            }

            return cachedContext.context
        }

        // Perform extraction
        do {
            await MainActor.run {
                isExtracting = true
                contextStatus = "Extracting content..."
            }

            let context = try await performContentExtraction(from: webView, tab: tab)

            // Cache the result
            cacheContext(context, for: url)

            await MainActor.run {
                lastExtractedContext = context
                lastExtractionTime = Date()
                contextStatus = "Context extracted"
                isExtracting = false
            }

            return context
        } catch {
            await MainActor.run {
                contextStatus = "Extraction failed: \(error.localizedDescription)"
                isExtracting = false
            }
            AppLog.error("Context extraction failed: \(error)")
            return nil
        }
    }

    /// Returns a rich, structured context string for the AI model by combining the current page data
    /// with optional browsing-history context. The page section includes title, URL, word count,
    /// a list of headings & prominent links, and finally the raw (truncated) body text.
    func getFormattedContext(from context: WebpageContext?, includeHistory: Bool = true) -> String? {
        var sections: [String] = []

        // 1. Current page
        if let context = context {
            let formattedContext = formatWebpageContext(context)
            sections.append(formattedContext)
            if AppLog.isVerboseEnabled {
                AppLog.debug(
                    "Formatted context length: \(formattedContext.count) from \(context.title)")
            }
        }

        // 2. Browsing history context (only if enabled)
        if includeHistory, isHistoryContextEnabled, let historyContext = getHistoryContext() {
            sections.append(historyContext)
            if AppLog.isVerboseEnabled {
                AppLog.debug("Including history context: length=\(historyContext.count)")
            }
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Private Methods

    private func formatWebpageContext(_ ctx: WebpageContext) -> String {
        let formattedResult = """
        Current webpage context:
        • Title: \(ctx.title)
        • URL: \(ctx.url)
        • Words: \(ctx.wordCount), Quality: \(ctx.contentQuality)%
        • Headings: \(ctx.headings.joined(separator: ", "))
        • Links: \(ctx.links.joined(separator: ", "))

        Full content (truncated to \(maxContentLength) chars):
        \(ctx.text)
        """
        return formattedResult
    }

    private func performContentExtraction(from webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        // ENHANCED: Multi-strategy content extraction with comprehensive fallbacks

        var bestContext: WebpageContext?
        var extractionStrategies: [ExtractionStrategy] = []

        // Determine extraction strategies based on content
        if webView.url?.absoluteString.contains("spa") == true || 
           webView.url?.absoluteString.contains("react") == true {
            extractionStrategies = [.lazyLoadScroll, .enhancedJavaScript, .emergencyExtraction]
        } else {
            extractionStrategies = [.enhancedJavaScript, .lazyLoadScroll, .emergencyExtraction]
        }

        // Try each strategy until we get acceptable content
        for strategy in extractionStrategies {
            do {
                let context = try await executeExtractionStrategy(strategy, webView: webView, tab: tab)
                
                if isAcceptableContext(context) {
                    bestContext = context
                    break
                }
                
                // Keep the best context found so far
                if bestContext == nil || context.contentQuality > bestContext!.contentQuality {
                    bestContext = context
                }
                
            } catch {
                AppLog.debug("Strategy \(strategy) failed: \(error)")
                continue
            }
        }

        guard let finalContext = bestContext else {
            throw ContextError.extractionTimeout
        }

        return finalContext
    }

    private func executeExtractionStrategy(_ strategy: ExtractionStrategy, webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        switch strategy {
        case .enhancedJavaScript:
            return try await performJavaScriptExtraction(webView: webView, tab: tab)

        case .networkInterception:
            // For now, fall back to JavaScript - network interception would require WKURLScheme handling
            return try await performJavaScriptExtraction(webView: webView, tab: tab)

        case .lazyLoadScroll:
            return try await performLazyLoadExtraction(webView: webView, tab: tab)

        case .emergencyExtraction:
            return try await performEmergencyExtraction(webView: webView, tab: tab)
        }
    }

    private func performJavaScriptExtraction(webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<WebpageContext, Error>) in
            let script = contentExtractionJavaScript

            // Set timeout for JavaScript execution
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(contentExtractionTimeout * 1_000_000_000))
                cont.resume(throwing: ContextError.extractionTimeout)
            }

            // Execute JavaScript on main thread
            Task { @MainActor [weak self] in
                do {
                    let result = try await webView.evaluateJavaScript(script)
                    timeoutTask.cancel()
                    guard let data = result as? [String: Any] else {
                        cont.resume(throwing: ContextError.invalidResponse)
                        return
                    }
                    do {
                        let context = try self?.parseExtractionResult(data, from: webView, tab: tab)
                            ?? WebpageContext(
                                url: webView.url?.absoluteString ?? "", title: "", text: "",
                                headings: [], links: [], wordCount: 0, extractionDate: Date(),
                                tabId: tab.id)
                        cont.resume(returning: context)
                    } catch {
                        cont.resume(throwing: error)
                    }
                } catch {
                    timeoutTask.cancel()
                    cont.resume(throwing: ContextError.javascriptError(error.localizedDescription))
                }
            }
        }
    }

    private func performLazyLoadExtraction(webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        // First trigger lazy loading
        await triggerLazyLoadScroll(on: webView)

        // Wait for content to load
        try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

        // Then perform JavaScript extraction
        return try await performJavaScriptExtraction(webView: webView, tab: tab)
    }

    private func performEmergencyExtraction(webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        // Simplified extraction that just gets all visible text
        let emergencyScript = """
            (function() {
                try {
                    var title = document.title || '';
                    var url = window.location.href;
                    var bodyText = document.body.innerText || document.body.textContent || '';
                    
                    // Clean basic content
                    var cleanedText = bodyText
                        .replace(/\\s+/g, ' ')
                        .replace(/\\n+/g, '\\n')
                        .trim();
                    
                    var wordCount = cleanedText.split(/\\s+/).filter(w => w.length > 0).length;
                    
                    return {
                        title: title,
                        url: url,
                        text: cleanedText,
                        headings: [],
                        links: [],
                        wordCount: wordCount,
                        contentQuality: Math.min(100, Math.max(20, wordCount / 10)),
                        isContentStable: true,
                        frameworksDetected: [],
                        extractionAttempt: 1
                    };
                } catch(e) {
                    return {
                        title: 'Error',
                        url: window.location.href || '',
                        text: 'Content extraction failed: ' + e.message,
                        headings: [],
                        links: [],
                        wordCount: 0,
                        contentQuality: 0,
                        isContentStable: true,
                        frameworksDetected: [],
                        extractionAttempt: 1
                    };
                }
            })();
            """

        return try await withCheckedThrowingContinuation { cont in
            Task { @MainActor [weak self] in
                do {
                    let result = try await webView.evaluateJavaScript(emergencyScript)
                    guard let data = result as? [String: Any] else {
                        cont.resume(throwing: ContextError.invalidResponse)
                        return
                    }
                    do {
                        let context = try self?.parseExtractionResult(data, from: webView, tab: tab)
                            ?? WebpageContext(
                                url: webView.url?.absoluteString ?? "", title: "", text: "",
                                headings: [], links: [], wordCount: 0, extractionDate: Date(),
                                tabId: tab.id)
                        cont.resume(returning: context)
                    } catch {
                        cont.resume(throwing: error)
                    }
                } catch {
                    cont.resume(throwing: ContextError.javascriptError(error.localizedDescription))
                }
            }
        }
    }

    private func parseExtractionResult(_ data: [String: Any], from webView: WKWebView, tab: Tab) throws -> WebpageContext {
        guard let rawText = data["text"] as? String,
            let title = data["title"] as? String,
            let url = data["url"] as? String
        else {
            throw ContextError.missingRequiredFields
        }

        let headings = data["headings"] as? [String] ?? []
        let links = data["links"] as? [String] ?? []
        let wordCount = data["wordCount"] as? Int ?? 0
        let contentQuality = data["contentQuality"] as? Int ?? 50
        let isContentStable = data["isContentStable"] as? Bool ?? true
        let frameworksDetected = data["frameworksDetected"] as? [String] ?? []
        let extractionAttempt = data["extractionAttempt"] as? Int ?? 1

        // Clean and truncate content
        let cleanedText = cleanExtractedContent(rawText)
        let finalText = maxContentLength > 0 ? truncateContent(cleanedText) : cleanedText

        return WebpageContext(
            url: url,
            title: title,
            text: finalText,
            headings: headings,
            links: links,
            wordCount: wordCount,
            extractionDate: Date(),
            tabId: tab.id,
            contentQuality: contentQuality,
            isContentStable: isContentStable,
            frameworksDetected: frameworksDetected,
            extractionAttempt: extractionAttempt
        )
    }

    private func cleanExtractedContent(_ text: String) -> String {
        // Remove CSS and HTML artifacts first
        var cleaned = text

        // Remove CSS rules and selectors
        cleaned = cleaned.replacingOccurrences(
            of: "\\.[a-zA-Z0-9_-]+\\s*\\{[^}]*\\}", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(
            of: "#[a-zA-Z0-9_-]+\\s*\\{[^}]*\\}", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(
            of: "[a-zA-Z0-9_-]+\\s*\\{[^}]*\\}", with: "", options: .regularExpression)

        // Remove CSS property patterns
        cleaned = cleaned.replacingOccurrences(
            of: "[a-zA-Z-]+:\\s*[^;]+;", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(
            of: "\\.([-_a-zA-Z0-9]+)", with: "", options: .regularExpression)

        // Remove HTML tags
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Remove JavaScript patterns
        cleaned = cleaned.replacingOccurrences(
            of: "function\\s*\\([^)]*\\)\\s*\\{[^}]*\\}", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(
            of: "\\([^)]*\\)\\s*=>\\s*[^;\\n]+[;\\n]?", with: "", options: .regularExpression)

        // Remove common web artifacts
        cleaned = cleaned.replacingOccurrences(
            of: "\\b(fill|stroke|url|rgba?|#[0-9a-fA-F]{3,8})\\b", with: "",
            options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(
            of: "\\b(px|em|rem|vh|vw|%|deg)\\b", with: "", options: .regularExpression)

        // Remove excessive whitespace and clean up content
        cleaned = cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n+", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private func truncateContent(_ text: String) -> String {
        // If no limit set or text is within limit, return as-is
        if maxContentLength == 0 || text.count <= maxContentLength {
            return text
        }

        // Truncate at word boundary
        let truncated = String(text.prefix(maxContentLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            let result = String(truncated[..<lastSpace])
            return result + "... (content truncated)"
        }

        return String(text.prefix(maxContentLength)) + "... (content truncated)"
    }

    private var contentExtractionJavaScript: String {
        """
        (function() {
            // Enhanced content extraction with modern JavaScript
            try {
                var title = document.title || '';
                var url = window.location.href;
                var bodyText = document.body.innerText || document.body.textContent || '';
                
                // Extract headings
                var headings = [];
                var headingElements = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
                headingElements.forEach(function(heading) {
                    if (heading.textContent && heading.textContent.trim()) {
                        headings.push(heading.textContent.trim());
                    }
                });
                
                // Extract prominent links
                var links = [];
                var linkElements = document.querySelectorAll('a[href]');
                var linkCount = 0;
                linkElements.forEach(function(link) {
                    if (linkCount < 10 && link.textContent && link.textContent.trim() && link.href) {
                        links.push(link.textContent.trim() + ' (' + link.href + ')');
                        linkCount++;
                    }
                });
                
                // Clean content
                var cleanedText = bodyText
                    .replace(/\\s+/g, ' ')
                    .replace(/\\n+/g, '\\n')
                    .trim();
                
                var wordCount = cleanedText.split(/\\s+/).filter(w => w.length > 0).length;
                var contentQuality = Math.min(100, Math.max(20, wordCount / 10));
                
                return {
                    title: title,
                    url: url,
                    text: cleanedText,
                    headings: headings.slice(0, 20),
                    links: links.slice(0, 10),
                    wordCount: wordCount,
                    contentQuality: contentQuality,
                    isContentStable: true,
                    frameworksDetected: [],
                    extractionAttempt: 1
                };
            } catch(e) {
                return {
                    title: 'Error',
                    url: window.location.href || '',
                    text: 'Content extraction failed: ' + e.message,
                    headings: [],
                    links: [],
                    wordCount: 0,
                    contentQuality: 0,
                    isContentStable: true,
                    frameworksDetected: [],
                    extractionAttempt: 1
                };
            }
        })();
        """
    }

    /// Programmatically scrolls the page to trigger lazy-loaded content
    private func triggerLazyLoadScroll(on webView: WKWebView) async {
        let js = "(function(){ const scrollBottom = () => window.scrollTo(0, document.body.scrollHeight); scrollBottom(); setTimeout(scrollBottom, 200); setTimeout(() => window.scrollTo(0,0), 400); })();"
        do {
            _ = try await webView.evaluateJavaScript(js)
        } catch {
            // Ignore JavaScript errors during lazy load scrolling
        }
    }

    // MARK: - History Context

    func getHistoryContext() -> String? {
        guard isHistoryContextEnabled else { return nil }
        
        let historyItems = extractRelevantHistory()
        guard !historyItems.isEmpty else { return nil }
        
        var historyParts: [String] = ["Recent browsing history context:"]
        
        for item in historyItems.prefix(maxHistoryItems) {
            let timeAgo = formatTimeAgo(item.lastVisitDate)
            let title = (item.title?.isEmpty ?? true) ? "Untitled" : item.title!
            let domain = extractDomain(from: item.url) ?? "Unknown"
            
            historyParts.append("• [\(timeAgo)] \(title) (\(domain))")
        }
        
        let result = historyParts.joined(separator: "\n")
        return result.count <= maxHistoryContentLength ? result : String(result.prefix(maxHistoryContentLength)) + "..."
    }

    private func extractRelevantHistory() -> [HistoryItem] {
        let historyService = HistoryService.shared
        let cutoffDate = Date().addingTimeInterval(-maxHistoryDays)
        
        return historyService.recentHistory
            .filter { $0.lastVisitDate >= cutoffDate }
            .filter { !shouldExcludeFromHistoryContext($0.url) }
            .sorted { $0.lastVisitDate > $1.lastVisitDate }
    }

    private func shouldExcludeFromHistoryContext(_ url: String) -> Bool {
        let excludePatterns = [
            "chrome://", "webkit://", "about:", "localhost", "127.0.0.1",
            "file://", "data:", "javascript:"
        ]
        return excludePatterns.contains { url.hasPrefix($0) }
    }

    private func extractDomain(from url: String) -> String? {
        guard let urlObj = URL(string: url) else { return nil }
        return urlObj.host
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { // Less than 1 hour
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 { // Less than 1 day
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    // MARK: - Cache Management

    private func getCachedContext(for url: String) -> CachedContext? {
        cleanExpiredCache()
        
        guard let cached = contextCache[url] else { return nil }
        
        // Update access order for LRU
        if let index = cacheAccessOrder.firstIndex(of: url) {
            cacheAccessOrder.remove(at: index)
        }
        cacheAccessOrder.append(url)
        
        // Update access count
        contextCache[url]?.accessCount += 1
        
        return cached
    }

    private func cacheContext(_ context: WebpageContext, for url: String) {
        // Ensure we don't exceed cache size
        while contextCache.count >= maxCacheSize {
            evictLeastRecentlyUsed()
        }
        
        let cached = CachedContext(context: context, cachedAt: Date(), accessCount: 1)
        contextCache[url] = cached
        
        // Update access order
        if let index = cacheAccessOrder.firstIndex(of: url) {
            cacheAccessOrder.remove(at: index)
        }
        cacheAccessOrder.append(url)
    }

    private func cleanExpiredCache() {
        let cutoffDate = Date().addingTimeInterval(-cacheExpirationTime)
        let expiredUrls = contextCache.compactMap { (key, value) in
            value.cachedAt < cutoffDate ? key : nil
        }
        
        for url in expiredUrls {
            contextCache.removeValue(forKey: url)
            if let index = cacheAccessOrder.firstIndex(of: url) {
                cacheAccessOrder.remove(at: index)
            }
        }
    }

    private func evictLeastRecentlyUsed() {
        guard let lruUrl = cacheAccessOrder.first else { return }
        contextCache.removeValue(forKey: lruUrl)
        cacheAccessOrder.removeFirst()
    }

    // MARK: - Utility Methods

    private func isAcceptableContext(_ context: WebpageContext) -> Bool {
        // Enhanced context quality assessment
        guard context.wordCount > 50 else { return false }
        guard context.contentQuality > 30 else { return false }
        guard !context.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        
        return true
    }

    func canExtractContext(from tabManager: TabManager) -> Bool {
        guard let activeTab = tabManager.activeTab,
              let webView = activeTab.webView,
              let url = webView.url else { return false }
        
        let supportedSchemes = ["http", "https"]
        return supportedSchemes.contains(url.scheme?.lowercased() ?? "")
    }

    // MARK: - Configuration

    func configureHistoryContext(enabled: Bool, scope: HistoryContextScope) {
        isHistoryContextEnabled = enabled
        historyContextScope = scope
    }

    func clearContextCache() {
        contextCache.removeAll()
        cacheAccessOrder.removeAll()
        AppLog.debug("Context cache cleared")
    }

    func getCacheStatistics() -> (size: Int, hitRate: Double, avgQuality: Double) {
        let size = contextCache.count
        let totalAccesses = contextCache.values.reduce(0) { $0 + $1.accessCount }
        let hitRate = totalAccesses > 0 ? Double(contextCache.count) / Double(totalAccesses) : 0.0
        let avgQuality = contextCache.values.isEmpty ? 0.0 : 
            contextCache.values.reduce(0.0) { $0 + Double($1.context.contentQuality) } / Double(contextCache.count)
        
        return (size: size, hitRate: hitRate, avgQuality: avgQuality)
    }
}

// MARK: - Supporting Types

/// Cached context entry with metadata
struct CachedContext {
    let context: WebpageContext
    let cachedAt: Date
    var accessCount: Int
}

/// Represents extracted webpage content and metadata
struct WebpageContext: Identifiable, Codable {
    let id: UUID
    let url: String
    let title: String
    let text: String
    let headings: [String]
    let links: [String]
    let wordCount: Int
    let extractionDate: Date
    let tabId: UUID
    let contentQuality: Int
    let isContentStable: Bool
    let frameworksDetected: [String]
    let extractionAttempt: Int
    
    init(url: String, title: String, text: String, headings: [String], links: [String], 
         wordCount: Int, extractionDate: Date, tabId: UUID, contentQuality: Int = 50, 
         isContentStable: Bool = true, frameworksDetected: [String] = [], extractionAttempt: Int = 1) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.text = text
        self.headings = headings
        self.links = links
        self.wordCount = wordCount
        self.extractionDate = extractionDate
        self.tabId = tabId
        self.contentQuality = contentQuality
        self.isContentStable = isContentStable
        self.frameworksDetected = frameworksDetected
        self.extractionAttempt = extractionAttempt
    }

    var qualityDescription: String {
        switch contentQuality {
        case 80...: return "Excellent"
        case 60..<80: return "Good"
        case 40..<60: return "Fair"
        case 20..<40: return "Poor"
        default: return "Very Poor"
        }
    }
    
    var isHighQuality: Bool {
        return contentQuality >= 60 && wordCount > 200
    }
    
    var shouldRetry: Bool {
        return contentQuality < 40 || wordCount < 100 || !isContentStable
    }
}

/// History context scope options
enum HistoryContextScope: String, CaseIterable {
    case recent = "recent"
    case today = "today"
    case lastHour = "lastHour"
    case mostVisited = "mostVisited"
    
    var displayName: String {
        switch self {
        case .recent: return "Recent"
        case .today: return "Today"
        case .lastHour: return "Last Hour"
        case .mostVisited: return "Most Visited"
        }
    }
}

/// Content extraction strategies
enum ExtractionStrategy: CaseIterable {
    case enhancedJavaScript
    case networkInterception
    case lazyLoadScroll
    case emergencyExtraction
    
    var displayName: String {
        switch self {
        case .enhancedJavaScript: return "Enhanced JavaScript"
        case .networkInterception: return "Network Interception"
        case .lazyLoadScroll: return "Lazy-Load Scroll"
        case .emergencyExtraction: return "Emergency DOM"
        }
    }
}

/// Context extraction errors
enum ContextError: LocalizedError {
    case noWebView
    case extractionTimeout
    case javascriptError(String)
    case invalidResponse
    case missingRequiredFields
    case contentTooLarge
    
    var errorDescription: String? {
        switch self {
        case .noWebView:
            return "No WebView available for content extraction"
        case .extractionTimeout:
            return "Content extraction timed out"
        case .javascriptError(let message):
            return "JavaScript error: \(message)"
        case .invalidResponse:
            return "Invalid response from content extraction"
        case .missingRequiredFields:
            return "Missing required fields in extraction result"
        case .contentTooLarge:
            return "Webpage content is too large to process"
        }
    }
}