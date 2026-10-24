import WebKit
import UIKit

@MainActor
final class WebViewCoordinator: NSObject {
    weak var tab: BrowserTab?
    weak var devToolsVM: DeveloperToolsViewModel?
    weak var browserVM: BrowserViewModel?
    private var aiFilter: AIContentFilter?
    private var scanTask: Task<Void, Never>?
    private var pageSession: PageScanSession?
    private var isPageActive = false
    private var pageFinishedLoading = false
    private var hideUnsafe = false
    private var showMarkers = false
    private var pageGeneration = 0
    private var lastFilteringEnabled: Bool?
    private var lastHideUnsafe: Bool?
    private var lastShowMarkers: Bool?
    private var lastForceDarkMode: Bool?
    private var progressObservation: NSKeyValueObservation?

    private let scanBatchSize = 4

    // Content rules must be attached before navigation. Track desired/applied state so
    // SwiftUI updates cannot race the initial asynchronous rule-list compilation.
    private var desiredAdBlockingEnabled = true
    private var appliedAdBlockingEnabled: Bool?
    private var isConfiguringAdBlocking = false

    init(tab: BrowserTab, devToolsVM: DeveloperToolsViewModel, browserVM: BrowserViewModel) {
        self.tab = tab
        self.devToolsVM = devToolsVM
        self.browserVM = browserVM
        self.aiFilter = AIContentFilter()
        super.init()
        tab.scanVisibilityHandler = { [weak self, weak tab] isActive in
            guard let self, let webView = tab?.webView else { return }
            self.updatePageActivity(
                isActive: isActive,
                filteringEnabled: self.browserVM?.aiFilterEnabled == true,
                showMarkers: self.browserVM?.aiShowScanMarkers == true,
                hideUnsafe: self.browserVM?.aiRemoveUnsafe == true,
                webView: webView
            )
        }
    }

    @discardableResult
    func configureAdBlocking(enabled: Bool, on webView: WKWebView) async -> Bool {
        desiredAdBlockingEnabled = enabled
        guard !isConfiguringAdBlocking else { return false }

        isConfiguringAdBlocking = true
        defer { isConfiguringAdBlocking = false }
        var changed = false

        while appliedAdBlockingEnabled != desiredAdBlockingEnabled {
            let target = desiredAdBlockingEnabled
            var ruleList: WKContentRuleList?
            if target {
                ruleList = try? await ContentBlocker.shared.ruleList()
            }

            // The setting may have changed while the rule list was compiling.
            guard target == desiredAdBlockingEnabled else { continue }

            webView.configuration.userContentController.removeAllContentRuleLists()
            if let ruleList { webView.configuration.userContentController.add(ruleList) }
            appliedAdBlockingEnabled = target
            changed = true
        }

        return changed
    }

    func updatePageActivity(
        isActive: Bool,
        filteringEnabled: Bool,
        showMarkers: Bool,
        hideUnsafe: Bool,
        webView: WKWebView
    ) {
        let becameActive = isActive && !isPageActive
        let wasFilteringEnabled = lastFilteringEnabled ?? false
        let hideChanged = lastHideUnsafe != hideUnsafe
        let markersChanged = lastShowMarkers != showMarkers

        isPageActive = isActive
        self.hideUnsafe = hideUnsafe
        self.showMarkers = showMarkers
        lastFilteringEnabled = filteringEnabled
        lastHideUnsafe = hideUnsafe
        lastShowMarkers = showMarkers

        if markersChanged {
            webView.evaluateJavaScript(JavaScriptInjector.setMarkersJS(showMarkers), completionHandler: nil)
        }

        if hideChanged {
            webView.evaluateJavaScript(JavaScriptInjector.setUnsafeHiddenJS(hideUnsafe), completionHandler: nil)
        }

        guard isActive, filteringEnabled else {
            if wasFilteringEnabled || pageSession != nil || scanTask != nil {
                cancelPageScan(webView: webView, clearLabels: !filteringEnabled)
            }
            return
        }

        if (becameActive || pageSession == nil), pageFinishedLoading {
            beginPageScan(webView: webView)
        }
    }

    func applyDarkMode(_ enabled: Bool, on webView: WKWebView) {
        guard lastForceDarkMode != enabled else { return }
        lastForceDarkMode = enabled
        let script = enabled
            ? JavaScriptInjector.darkModeCSS().source
            : JavaScriptInjector.removeDarkModeJS()
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func cancelPageScan(webView: WKWebView, clearLabels: Bool) {
        scanTask?.cancel()
        scanTask = nil
        pageSession?.cancel()
        pageSession = nil
        webView.evaluateJavaScript(JavaScriptInjector.stopMutationObserverJS(), completionHandler: nil)
        if clearLabels {
            webView.evaluateJavaScript(JavaScriptInjector.clearAILabelsJS(), completionHandler: nil)
        }
        if browserVM?.currentTab?.id == tab?.id {
            devToolsVM?.clearAIResults()
        }
        // A scan drainer that exits because its session was replaced never
        // reaches finishScanTask; without clearing here the status bar stays
        // "Analyzing N/M blocks" forever — the reported stuck state.
        devToolsVM?.aiIsAnalyzing = false
    }

    private func beginPageScan(webView: WKWebView) {
        cancelPageScan(webView: webView, clearLabels: false)
        guard let tabID = tab?.id,
              browserVM?.currentTab?.id == tabID,
              browserVM?.aiFilterEnabled == true else { return }

        isPageActive = true
        let session = PageScanSession(tabID: tabID, navigationGeneration: pageGeneration)
        pageSession = session
        devToolsVM?.clearAIResults()
        webView.evaluateJavaScript(JavaScriptInjector.setUnsafeHiddenJS(hideUnsafe), completionHandler: nil)
        webView.evaluateJavaScript(JavaScriptInjector.injectMutationObserverJS(), completionHandler: nil)

        let sessionID = session.id
        scanTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            self.log("🔍 Extracting visible content blocks…")
            guard let json = await self.evalJS(webView, JavaScriptInjector.extractContentBlocksJS()),
                  self.isSessionCurrent(sessionID),
                  let data = json.data(using: .utf8),
                  let extracted = try? JSONDecoder().decode([PageScanCandidate].self, from: data)
            else {
                if self.isSessionCurrent(sessionID) { self.finishScanTask(sessionID: sessionID) }
                return
            }

            let initial = Array(extracted.prefix(40))
            for candidate in initial { self.pageSession?.enqueue(candidate) }
            self.devToolsVM?.aiTotalCount = initial.count
            self.log("📄 Queued \(initial.count) visible, new or changed blocks")
            await self.drainSession(sessionID: sessionID, webView: webView)
        }
    }

    private func startMutationDrainIfNeeded(webView: WKWebView) {
        guard scanTask == nil, let sessionID = pageSession?.id else { return }
        scanTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self.drainSession(sessionID: sessionID, webView: webView)
        }
    }

    private func drainSession(sessionID: UUID, webView: WKWebView) async {
        guard isSessionCurrent(sessionID) else { return }
        devToolsVM?.aiIsAnalyzing = true

        let useLaya: Bool
        do {
            log("🤖 Preparing on-device Laya MLX…")
            try await aiFilter?.prepareLaya()
            useLaya = true
        } catch {
            useLaya = false
            if isSessionCurrent(sessionID) {
                log("⚠️ Laya unavailable — using keyword fallback")
            }
        }

        while isSessionCurrent(sessionID), !Task.isCancelled {
            guard let batch = pageSession?.dequeueBatch(limit: scanBatchSize), !batch.isEmpty else { break }
            webView.evaluateJavaScript(JavaScriptInjector.markAllPendingJS(candidates: batch, showMarkers: showMarkers), completionHandler: nil)

            let results = await aiFilter?.classifyBatch(
                texts: batch.map(\.text),
                useLaya: useLaya
            ) ?? []
            guard isSessionCurrent(sessionID), !Task.isCancelled else { return }

            var updates: [JavaScriptInjector.LabelUpdate] = []
            for (offset, candidate) in batch.enumerated() where offset < results.count {
                let result = results[offset] ?? ContentClassificationResult(
                    isSafe: true,
                    reason: "Too short to analyze",
                    method: "skip",
                    confidence: nil,
                    latencyMs: nil
                )
                pageSession?.markProcessed(candidate)
                updates.append(JavaScriptInjector.LabelUpdate(
                    xpath: candidate.xpath,
                    fingerprint: candidate.fingerprint,
                    isSafe: result.isSafe,
                    reason: result.reason,
                    hideUnsafe: hideUnsafe
                ))

                let preview = String(candidate.text.prefix(60))
                log("[\(result.method)] \(result.isSafe ? "✅" : "🔴") \"\(preview)\" — \(result.reason)")
                devToolsVM?.addAIResult(AIResult(
                    xpath: candidate.xpath,
                    isSafe: result.isSafe,
                    reason: result.reason,
                    preview: preview
                ))
            }

            if !updates.isEmpty {
                webView.evaluateJavaScript(
                    JavaScriptInjector.updateLabelsJS(updates),
                    completionHandler: nil
                )
            }
            await Task.yield()
        }

        finishScanTask(sessionID: sessionID)
    }

    private func finishScanTask(sessionID: UUID) {
        guard isSessionCurrent(sessionID) else { return }
        scanTask = nil
        devToolsVM?.aiIsAnalyzing = false
        if pageSession?.hasPendingCandidates == true, let webView = tab?.webView {
            startMutationDrainIfNeeded(webView: webView)
        }
    }

    private func isSessionCurrent(_ sessionID: UUID) -> Bool {
        guard isPageActive, let session = pageSession else { return false }
        return session.accepts(
            sessionID: sessionID,
            selectedTabID: browserVM?.currentTab?.id,
            navigationGeneration: pageGeneration
        )
    }

    private func evalJS(_ webView: WKWebView, _ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result as? String)
            }
        }
    }

    private func log(_ message: String) {
        print("[Drome AI] \(message)")
        devToolsVM?.addConsoleEntry(ConsoleEntry(
            level: .info,
            message: message,
            source: "Drome AI",
            line: nil,
            column: nil,
            timestamp: .now,
            tabID: tab?.id ?? UUID()
        ))
    }
}

// MARK: - WKNavigationDelegate

extension WebViewCoordinator: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {

        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Website blocking
        if let bvm = browserVM, bvm.isDomainBlocked(url) {
            decisionHandler(.cancel)
            showBlockedPage(webView: webView, url: url)
            return
        }

        // Handle new tab links (target=_blank)
        if navigationAction.targetFrame == nil {
            browserVM?.addNewTab(url: url)
            decisionHandler(.cancel)
            return
        }

        // Log navigation
        let entry = NetworkEntry(
            id: UUID().uuidString,
            url: url.absoluteString,
            method: navigationAction.request.httpMethod ?? "GET",
            type: .navigation,
            startTime: .now,
            tabID: tab?.id ?? UUID()
        )
        devToolsVM?.addNetworkRequest(entry)

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tab?.isLoading = true
        tab?.estimatedProgress = 0
        tab?.errorMessage = nil
        tab?.snapshot = nil
        progressObservation?.invalidate()
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            guard let progress = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.tab?.estimatedProgress = progress
            }
        }

        pageFinishedLoading = false
        pageGeneration += 1
        lastForceDarkMode = nil
        cancelPageScan(webView: webView, clearLabels: true)
        browserVM?.readingModeActive = false
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        tab?.url = webView.url
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab?.isLoading = false
        tab?.estimatedProgress = 1.0
        tab?.url = webView.url
        tab?.title = webView.title ?? ""
        tab?.canGoBack = webView.canGoBack
        tab?.canGoForward = webView.canGoForward
        pageFinishedLoading = true

        progressObservation?.invalidate()
        progressObservation = nil

        // Load favicon
        loadFavicon(for: webView)

        // Apply dark mode if needed
        if browserVM?.forceDarkMode == true {
            lastForceDarkMode = nil
            applyDarkMode(true, on: webView)
        }

        if browserVM?.aiFilterEnabled == true,
           browserVM?.currentTab?.id == tab?.id {
            isPageActive = true
            hideUnsafe = browserVM?.aiRemoveUnsafe == true
            showMarkers = browserVM?.aiShowScanMarkers == true
            beginPageScan(webView: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        tab?.isLoading = false
        progressObservation?.invalidate()
        progressObservation = nil
        tab?.errorMessage = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        tab?.isLoading = false
        progressObservation?.invalidate()
        progressObservation = nil
        let nsErr = error as NSError
        if nsErr.code != NSURLErrorCancelled {
            showErrorPage(webView: webView, error: error)
        }
    }

    // MARK: - Downloads

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let mime = navigationResponse.response.mimeType ?? ""
        let downloadable = !navigationResponse.canShowMIMEType || mime == "application/octet-stream"
        decisionHandler(downloadable ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: - Helpers

    private func showBlockedPage(webView: WKWebView, url: URL) {
        let domain = url.host ?? url.absoluteString
        let escaped = htmlEscape(domain)
        let query = domain.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let html = """
        <html><body style="font-family:-apple-system;padding:40px;text-align:center;color:#666">
        <h2>🚫 Site Blocked</h2>
        <p><b>\(escaped)</b> is in your block list.</p>
        <p><a href="drome://unblock?domain=\(query)">Unblock this site</a></p>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func showErrorPage(webView: WKWebView, error: Error) {
        let nsErr = error as NSError
        let html = """
        <html><body style="font-family:-apple-system;padding:40px;text-align:center;color:#666">
        <h2>Cannot Open Page</h2>
        <p>\(htmlEscape(nsErr.localizedDescription))</p>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func loadFavicon(for webView: WKWebView) {
        guard let host = webView.url?.host,
              let url = URL(string: "https://\(host)/favicon.ico") else { return }
        Task { @MainActor [weak tab] in
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
                  let image = UIImage(data: data) else { return }
            tab?.favicon = image
        }
    }
}

// MARK: - WKUIDelegate

extension WebViewCoordinator: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if browserVM?.blockPopups == true { return nil }
        if let url = navigationAction.request.url {
            browserVM?.addNewTab(url: url)
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor () -> Void) {
        let alert = UIAlertController(title: frame.request.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        topViewController()?.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = UIAlertController(title: frame.request.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        topViewController()?.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor (String?) -> Void) {
        let alert = UIAlertController(title: frame.request.url?.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { tf in tf.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        topViewController()?.present(alert, animated: true)
    }

    private func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}

// MARK: - WKScriptMessageHandler

extension WebViewCoordinator: WKScriptMessageHandler {

    nonisolated func userContentController(_ ucc: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        Task { @MainActor in
            switch message.name {
            case "dromeConsole":
                handleConsoleMessage(message.body)
            case "dromeNetwork":
                handleNetworkMessage(message.body)
            case "dromeMutation":
                handleMutationMessage(message.body)
            case "dromeAIFilter":
                break
            default:
                break
            }
        }
    }

    private func handleConsoleMessage(_ body: Any) {
        guard let dict = body as? [String: Any] else { return }
        let levelStr = dict["level"] as? String ?? "log"
        let level = ConsoleLevel(rawValue: levelStr) ?? .log
        let message = dict["message"] as? String ?? ""
        let source = dict["source"] as? String ?? ""
        let line = dict["line"] as? Int
        let column = dict["column"] as? Int
        let ts = dict["timestamp"] as? Double ?? Date().timeIntervalSince1970 * 1000
        let entry = ConsoleEntry(
            level: level,
            message: message,
            source: source,
            line: line,
            column: column,
            timestamp: Date(timeIntervalSince1970: ts / 1000),
            tabID: tab?.id ?? UUID()
        )
        devToolsVM?.addConsoleEntry(entry)
    }

    private func handleMutationMessage(_ body: Any) {
        guard let dict = body as? [String: Any],
              let id = dict["id"] as? String,
              let text = dict["text"] as? String,
              let xpath = dict["xpath"] as? String,
              let fingerprint = dict["fingerprint"] as? String,
              browserVM?.aiFilterEnabled == true,
              browserVM?.currentTab?.id == tab?.id,
              isPageActive,
              let webView = tab?.webView else { return }

        let candidate = PageScanCandidate(
            id: id,
            xpath: xpath,
            text: text,
            fingerprint: fingerprint
        )
        if pageSession?.enqueue(candidate) == true {
            devToolsVM?.aiTotalCount += 1
            startMutationDrainIfNeeded(webView: webView)
        } else if pageSession == nil || pageSession?.isCancelled == true {
            // Diagnostic visibility for a dead mutation feed: tell silent
            // drops (dedup drops stay quiet — they are normal) apart from a
            // starving scan so infinite-scroll gaps are explainable.
            log("⚠️ Mutation candidate dropped: no active scan session — id=\(candidate.id), text=\"\(candidate.text.prefix(40))\"")
        }
    }

    private func handleNetworkMessage(_ body: Any) {
        guard let dict = body as? [String: Any] else { return }
        let type = dict["type"] as? String ?? "request"
        let id = dict["id"] as? String ?? UUID().uuidString
        let url = dict["url"] as? String ?? ""
        let method = dict["method"] as? String ?? "GET"

        switch type {
        case "request":
            let entry = NetworkEntry(
                id: id,
                url: url,
                method: method,
                type: method == "GET" ? .fetch : .xhr,
                startTime: .now,
                tabID: tab?.id ?? UUID()
            )
            devToolsVM?.addNetworkRequest(entry)

        case "response":
            let status = dict["status"] as? Int ?? 200
            let duration = (dict["duration"] as? Double ?? 0) / 1000
            let size = dict["size"] as? Int ?? 0
            devToolsVM?.updateNetworkResponse(id: id, status: status, duration: duration, size: size)

        case "error":
            let errorMsg = dict["error"] as? String ?? "Unknown error"
            devToolsVM?.markNetworkError(id: id, message: errorMsg)

        default:
            break
        }
    }
}

// MARK: - WKDownloadDelegate

extension WebViewCoordinator: WKDownloadDelegate {

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping @MainActor (URL?) -> Void) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = docs.appendingPathComponent(suggestedFilename)
        completionHandler(dest)

        Task { @MainActor in
            let item = DownloadItem(url: response.url ?? URL(string: "about:blank")!, localURL: dest)
            browserVM?.downloadItems.append(item)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        Task { @MainActor in
            if let idx = browserVM?.downloadItems.firstIndex(where: { !$0.isComplete }) {
                browserVM?.downloadItems[idx].isComplete = true
                browserVM?.downloadItems[idx].progress = 1.0
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        Task { @MainActor in
            if let idx = browserVM?.downloadItems.firstIndex(where: { !$0.isComplete }) {
                browserVM?.downloadItems[idx].error = error
            }
        }
    }

    func download(_ download: WKDownload,
                  didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}
