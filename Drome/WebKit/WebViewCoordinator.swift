import WebKit
import UIKit

@MainActor
final class WebViewCoordinator: NSObject {
    weak var tab: BrowserTab?
    weak var devToolsVM: DeveloperToolsViewModel?
    weak var browserVM: BrowserViewModel?
    private var aiFilter: AIContentFilter?
    private var aiAnalysisTask: Task<Void, Never>?

    // Live DOM mutation handling — debounced queue
    private var mutationDebounceTask: Task<Void, Never>?
    private var pendingMutations: [(text: String, xpath: String)] = []

    init(tab: BrowserTab, devToolsVM: DeveloperToolsViewModel, browserVM: BrowserViewModel) {
        self.tab = tab
        self.devToolsVM = devToolsVM
        self.browserVM = browserVM
        self.aiFilter = AIContentFilter()
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
        webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)

        // Cancel any in-flight AI analysis and clear old labels
        aiAnalysisTask?.cancel()
        aiAnalysisTask = nil
        mutationDebounceTask?.cancel()
        mutationDebounceTask = nil
        pendingMutations.removeAll()
        webView.evaluateJavaScript(JavaScriptInjector.stopMutationObserverJS(), completionHandler: nil)
        webView.evaluateJavaScript(JavaScriptInjector.clearAILabelsJS(), completionHandler: nil)
        devToolsVM?.clearAIResults()
        browserVM?.readingModeActive = false
    }

    override nonisolated func observeValue(forKeyPath keyPath: String?,
                                           of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?,
                                           context: UnsafeMutableRawPointer?) {
        guard keyPath == "estimatedProgress",
              let progress = (change?[.newKey] as? NSNumber)?.doubleValue else { return }
        Task { @MainActor in
            self.tab?.estimatedProgress = progress
        }
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

        webView.removeObserver(self, forKeyPath: "estimatedProgress")

        // Take a snapshot for the tab grid
        Task {
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = 200
            if let image = try? await webView.takeSnapshot(configuration: config) {
                tab?.snapshot = image
            }
        }

        // Load favicon
        loadFavicon(for: webView)

        // Apply dark mode if needed
        if browserVM?.forceDarkMode == true {
            let css = "html{filter:invert(1) hue-rotate(180deg)!important}img,video,canvas,picture{filter:invert(1) hue-rotate(180deg)!important}"
            let js = "var s=document.createElement('style');s.id='__drome_dark';s.textContent=`\(css)`;if(!document.getElementById('__drome_dark'))document.head.appendChild(s);"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // Run AI content analysis if enabled
        if browserVM?.aiFilterEnabled == true {
            let removeUnsafe = browserVM?.aiRemoveUnsafe ?? false
            let filter = aiFilter
            let dvm = devToolsVM
            let wv = webView
            aiAnalysisTask = Task { @MainActor in
                await filter?.analyzeAndLabel(webView: wv, devToolsVM: dvm, removeUnsafe: removeUnsafe)
                // After initial pass, watch for dynamically injected content
                guard !Task.isCancelled else { return }
                wv.evaluateJavaScript(JavaScriptInjector.injectMutationObserverJS(), completionHandler: nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        tab?.isLoading = false
        webView.removeObserver(self, forKeyPath: "estimatedProgress")
        tab?.errorMessage = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        tab?.isLoading = false
        webView.removeObserver(self, forKeyPath: "estimatedProgress")
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
        let html = """
        <html><body style="font-family:-apple-system;padding:40px;text-align:center;color:#666">
        <h2>🚫 Site Blocked</h2>
        <p><b>\(domain)</b> is in your block list.</p>
        <p><a href="drome://unblock?domain=\(domain)">Unblock this site</a></p>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func showErrorPage(webView: WKWebView, error: Error) {
        let nsErr = error as NSError
        let html = """
        <html><body style="font-family:-apple-system;padding:40px;text-align:center;color:#666">
        <h2>Cannot Open Page</h2>
        <p>\(nsErr.localizedDescription)</p>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func loadFavicon(for webView: WKWebView) {
        guard let host = webView.url?.host else { return }
        let faviconURL = "https://\(host)/favicon.ico"
        guard let url = URL(string: faviconURL) else { return }
        Task {
            if let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                tab?.favicon = img
            }
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
              let text = dict["text"] as? String,
              let xpath = dict["xpath"] as? String,
              browserVM?.aiFilterEnabled == true else { return }

        // Deduplicate — skip if we already have a result for this xpath
        if devToolsVM?.aiResults.contains(where: { $0.xpath == xpath }) == true { return }

        pendingMutations.append((text: text, xpath: xpath))

        // Debounce: reset the 2s timer on every incoming mutation
        mutationDebounceTask?.cancel()
        let mutations = pendingMutations
        let filter = aiFilter
        let dvm = devToolsVM
        let removeUnsafe = browserVM?.aiRemoveUnsafe ?? false
        guard let wv = tab?.webView else { return }

        mutationDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self.pendingMutations.removeAll()
            // Process up to 10 new blocks per batch to avoid overload
            for item in mutations.prefix(10) {
                guard !Task.isCancelled else { break }
                await filter?.classifySingleBlock(
                    text: item.text,
                    xpath: item.xpath,
                    webView: wv,
                    devToolsVM: dvm,
                    removeUnsafe: removeUnsafe
                )
            }
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
