import SwiftUI
import WebKit
import Combine

@MainActor
final class BrowserViewModel: ObservableObject {

    // MARK: - Tabs
    @Published var tabs: [BrowserTab] = []
    @Published var currentTabIndex: Int = 0

    // MARK: - UI State
    @Published var showTabGrid = false
    @Published var showDevTools = false
    @Published var showSettings = false
    @Published var showWebsiteBlocker = false
    @Published var showDownloads = false
    @Published var devToolsHeight: CGFloat = 300

    // MARK: - Settings
    @AppStorage("adBlockEnabled") var adBlockEnabled = true
    @AppStorage("aiFilterEnabled") var aiFilterEnabled = true
    @AppStorage("forceDarkMode") var forceDarkMode = false
    @AppStorage("jsEnabled") var jsEnabled = true
    @AppStorage("customUserAgent") var customUserAgent = ""
    @AppStorage("searchEngine") var searchEngine = "https://duckduckgo.com/?q="
    @AppStorage("blockPopups") var blockPopups = true
    @AppStorage("aiRemoveUnsafe") var aiRemoveUnsafe = false
    @AppStorage("layaMLXEndpoint") var layaMLXEndpoint = "http://127.0.0.1:8765"

    // Per-session state (resets on relaunch)
    @Published var readingModeActive = false

    // MARK: - Website Blocking
    @Published var blockedDomains: [BlockRule] = []

    // MARK: - Downloads
    @Published var downloadItems: [DownloadItem] = []

    var currentTab: BrowserTab? {
        guard tabs.indices.contains(currentTabIndex) else { return nil }
        return tabs[currentTabIndex]
    }

    init() {
        loadBlockedDomains()
        addNewTab(url: nil)
    }

    // MARK: - Tab Management

    func addNewTab(url: URL? = nil) {
        let tab = BrowserTab(url: url)
        tabs.append(tab)
        currentTabIndex = tabs.count - 1
        showTabGrid = false
    }

    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].webView?.stopLoading()
        tabs[index].webView = nil
        tabs.remove(at: index)
        if tabs.isEmpty {
            addNewTab()
        } else {
            currentTabIndex = min(currentTabIndex, tabs.count - 1)
        }
    }

    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        currentTabIndex = index
        showTabGrid = false
    }

    func duplicateTab() {
        guard let current = currentTab else { return }
        addNewTab(url: current.url)
    }

    // MARK: - Navigation

    func navigate(to rawInput: String) {
        guard let tab = currentTab else { return }
        let url = resolveURL(from: rawInput)
        tab.url = url
        if let wv = tab.webView, let url {
            wv.load(URLRequest(url: url))
        }
    }

    func goBack() {
        currentTab?.webView?.goBack()
    }

    func goForward() {
        currentTab?.webView?.goForward()
    }

    func reload() {
        currentTab?.webView?.reload()
    }

    func stopLoading() {
        currentTab?.webView?.stopLoading()
    }

    func hardReload() {
        guard let wv = currentTab?.webView else { return }
        wv.reloadFromOrigin()
    }

    // MARK: - URL Resolution

    func resolveURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }

        if trimmed.contains(".") && !trimmed.contains(" ") {
            if let url = URL(string: "https://" + trimmed) {
                return url
            }
        }

        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: searchEngine + query)
    }

    // MARK: - Blocked Domains

    func addBlockedDomain(_ domain: String) {
        let rule = BlockRule.domainRule(domain.lowercased())
        blockedDomains.append(rule)
        saveBlockedDomains()
    }

    func removeBlockedDomain(at offsets: IndexSet) {
        blockedDomains.remove(atOffsets: offsets)
        saveBlockedDomains()
    }

    func toggleBlockedDomain(_ rule: BlockRule) {
        if let idx = blockedDomains.firstIndex(where: { $0.id == rule.id }) {
            blockedDomains[idx].isEnabled.toggle()
            saveBlockedDomains()
        }
    }

    func isDomainBlocked(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return blockedDomains.contains { rule in
            rule.isEnabled && (host == rule.pattern || host.hasSuffix("." + rule.pattern))
        }
    }

    private func saveBlockedDomains() {
        let userRules = blockedDomains.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(userRules) {
            UserDefaults.standard.set(data, forKey: "blockedDomains")
        }
    }

    private func loadBlockedDomains() {
        if let data = UserDefaults.standard.data(forKey: "blockedDomains"),
           let rules = try? JSONDecoder().decode([BlockRule].self, from: data) {
            blockedDomains = rules
        }
    }

    // MARK: - Clipboard / Sharing

    func copyCurrentURL() {
        UIPasteboard.general.string = currentTab?.displayURL
    }
}


struct DownloadItem: Identifiable {
    let id = UUID()
    let url: URL
    var localURL: URL?
    var progress: Double = 0
    var isComplete = false
    var error: Error?
    var filename: String { url.lastPathComponent }
}
