import Combine
import Foundation
import SwiftUI
import WebKit

class TabManager: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var activeTab: Tab?
    @Published var recentlyClosedTabs: [Tab] = []

    private let maxRecentlyClosedTabs = 10
    private let maxConcurrentTabs = 50
    private var hibernationSubscription: AnyCancellable?

    init() {
        // Create initial tab
        createNewTab()

        // Setup hibernation integration
        setupHibernationIntegration()

        // Setup WebView collection for BackgroundResourceManager
        setupWebViewCollection()
    }

    // MARK: - Tab Operations
    @discardableResult
    func createNewTab(url: URL? = nil, isIncognito: Bool = false) -> Tab {
        let tab: Tab

        if isIncognito {
            // Create incognito tab through IncognitoSession
            tab = IncognitoSession.shared.createIncognitoTab(url: url)
        } else {
            tab = Tab(url: url, isIncognito: isIncognito)
        }

        tabs.append(tab)
        setActiveTab(tab)

        // Manage memory by hibernating old tabs
        manageTabMemory()

        return tab
    }

    @discardableResult
    func createNewTabInBackground(url: URL? = nil, isIncognito: Bool = false) -> Tab {
        let tab: Tab

        if isIncognito {
            // Create incognito tab through IncognitoSession
            tab = IncognitoSession.shared.createIncognitoTab(url: url)
        } else {
            tab = Tab(url: url, isIncognito: isIncognito)
        }

        tabs.append(tab)
        // Note: We do NOT call setActiveTab(tab) for background tabs

        // Manage memory by hibernating old tabs
        manageTabMemory()

        return tab
    }

    @discardableResult
    func createIncognitoTab(url: URL? = nil) -> Tab {
        return createNewTab(url: url, isIncognito: true)
    }

    func closeTab(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }

        // Handle incognito tab closure
        if tab.isIncognito {
            IncognitoSession.shared.closeIncognitoTab(tab)
        } else {
            // Add to recently closed (only for regular tabs)
            recentlyClosedTabs.insert(tab, at: 0)
            if recentlyClosedTabs.count > maxRecentlyClosedTabs {
                recentlyClosedTabs.removeLast()
            }
        }

        tabs.remove(at: index)

        // Select new active tab
        if activeTab?.id == tab.id {
            if index < tabs.count {
                setActiveTab(tabs[index])
            } else if index > 0 {
                setActiveTab(tabs[index - 1])
            } else {
                activeTab = nil
                // Notify that no active tab is available (context status should update)
                NotificationCenter.default.post(
                    name: .pageNavigationCompleted,
                    object: nil
                )
            }
        }

        // Create new tab if none remain
        if tabs.isEmpty {
            createNewTab()
        }
    }

    func reopenLastClosedTab() -> Tab? {
        guard let lastClosed = recentlyClosedTabs.first else { return nil }

        recentlyClosedTabs.removeFirst()
        let newTab = createNewTab(url: lastClosed.url, isIncognito: lastClosed.isIncognito)
        newTab.title = lastClosed.title
        newTab.favicon = lastClosed.favicon

        return newTab
    }

    func setActiveTab(_ tab: Tab) {
        // Don't do anything if this tab is already active
        guard activeTab?.id != tab.id else { return }

        // Deactivate current tab
        activeTab?.isActive = false

        // Activate new tab
        activeTab = tab
        tab.isActive = true
        tab.wakeUp()  // Wake up if hibernated

        // CRITICAL: Immediately update URLSynchronizer for instant URL bar updates
        URLSynchronizer.shared.updateFromTabSwitch(
            tabID: tab.id,
            url: tab.url,
            title: tab.title,
            isLoading: tab.isLoading,
            progress: tab.estimatedProgress,
            isHibernated: tab.isHibernated
        )

        // Notify that the active tab changed (for AI context status updates)
        NotificationCenter.default.post(
            name: .tabDidBecomeActive,
            object: tab
        )

        NotificationCenter.default.post(
            name: .pageNavigationCompleted,
            object: tab.id
        )

        // Tab switched successfully
    }

    func moveTab(from source: IndexSet, to destination: Int) {
        // Enhanced tab reordering with animation support
        guard let sourceIndex = source.first,
            sourceIndex != destination,
            sourceIndex >= 0 && sourceIndex < tabs.count,
            destination >= 0 && destination <= tabs.count
        else {
            return
        }

        // Perform the move with smooth animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            tabs.move(fromOffsets: source, toOffset: destination)
        }

        // Maintain active tab reference after reordering
        if let activeTab = activeTab, tabs.firstIndex(where: { $0.id == activeTab.id }) != nil {
            // Update any tab order-dependent logic here if needed
        }
    }

    // Enhanced reordering with better validation
    func moveTabSafely(fromIndex: Int, toIndex: Int) -> Bool {
        guard fromIndex != toIndex,
            fromIndex >= 0 && fromIndex < tabs.count,
            toIndex >= 0 && toIndex <= tabs.count
        else {
            return false
        }

        let adjustedToIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        guard adjustedToIndex >= 0 && adjustedToIndex < tabs.count else {
            return false
        }

        // Use haptic feedback for successful reorders
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
        }

        return true
    }

    // MARK: - Memory Management & Hibernation Integration

    private func setupHibernationIntegration() {
        // Listen for hibernation evaluation requests
        hibernationSubscription = NotificationCenter.default
            .publisher(for: .hibernationEvaluationRequested)
            .sink { [weak self] _ in
                self?.evaluateTabsForHibernation()
            }
    }

    private func manageTabMemory() {
        // Use the new TabHibernationManager for intelligent memory management
        evaluateTabsForHibernation()
    }

    private func evaluateTabsForHibernation() {
        // Delegate hibernation decisions to the TabHibernationManager
        TabHibernationManager.shared.evaluateTabs(tabs, activeTab: activeTab)
    }

    private func setupWebViewCollection() {
        // Listen for WebView collection requests from BackgroundResourceManager
        NotificationCenter.default.addObserver(
            forName: .collectActiveWebViews, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                let userInfo = notification.userInfo,
                let collector = userInfo["collector"] as? (WKWebView) -> Void
            else { return }

            // Collect all active WebViews from tabs
            for tab in self.tabs {
                if let webView = tab.webView {
                    collector(webView)
                }
            }
        }
    }

    deinit {
        hibernationSubscription?.cancel()
    }

    // MARK: - Additional Tab Operations
    func closeOtherTabs(except tab: Tab) {
        let tabsToClose = tabs.filter { $0.id != tab.id }
        for tabToClose in tabsToClose {
            closeTab(tabToClose)
        }
    }

    func closeTabsToTheRight(of tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }

        let tabsToClose = Array(tabs.suffix(from: index + 1))
        for tabToClose in tabsToClose {
            closeTab(tabToClose)
        }
    }

    // MARK: - Search and Filter
    func searchTabs(query: String) -> [Tab] {
        guard !query.isEmpty else { return tabs }

        return tabs.filter { tab in
            tab.title.lowercased().contains(query.lowercased())
                || tab.url?.absoluteString.lowercased().contains(query.lowercased()) == true
        }
    }

    // MARK: - Tab Navigation
    func selectNextTab() {
        guard let currentTab = activeTab,
            let currentIndex = tabs.firstIndex(where: { $0.id == currentTab.id })
        else { return }

        let nextIndex = (currentIndex + 1) % tabs.count
        setActiveTab(tabs[nextIndex])
    }

    func selectPreviousTab() {
        guard let currentTab = activeTab,
            let currentIndex = tabs.firstIndex(where: { $0.id == currentTab.id })
        else { return }

        let previousIndex = currentIndex == 0 ? tabs.count - 1 : currentIndex - 1
        setActiveTab(tabs[previousIndex])
    }

    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        setActiveTab(tabs[index])
    }

    func selectTabByNumber(_ number: Int) {
        let index = number - 1  // Convert 1-based to 0-based index
        selectTab(at: index)
    }

    // MARK: - Keyboard-based Tab Reordering

    /// Move the active tab one position to the left/up
    func moveActiveTabBackward() -> Bool {
        guard let activeTab = activeTab,
            let currentIndex = tabs.firstIndex(where: { $0.id == activeTab.id }),
            currentIndex > 0
        else {
            return false
        }

        return moveTabSafely(fromIndex: currentIndex, toIndex: currentIndex - 1)
    }

    /// Move the active tab one position to the right/down
    func moveActiveTabForward() -> Bool {
        guard let activeTab = activeTab,
            let currentIndex = tabs.firstIndex(where: { $0.id == activeTab.id }),
            currentIndex < tabs.count - 1
        else {
            return false
        }

        return moveTabSafely(fromIndex: currentIndex, toIndex: currentIndex + 1)
    }

    /// Move the active tab to the beginning of the tab list
    func moveActiveTabToStart() -> Bool {
        guard let activeTab = activeTab,
            let currentIndex = tabs.firstIndex(where: { $0.id == activeTab.id }),
            currentIndex > 0
        else {
            return false
        }

        return moveTabSafely(fromIndex: currentIndex, toIndex: 0)
    }

    /// Move the active tab to the end of the tab list
    func moveActiveTabToEnd() -> Bool {
        guard let activeTab = activeTab,
            let currentIndex = tabs.firstIndex(where: { $0.id == activeTab.id }),
            currentIndex < tabs.count - 1
        else {
            return false
        }

        return moveTabSafely(fromIndex: currentIndex, toIndex: tabs.count - 1)
    }
}
