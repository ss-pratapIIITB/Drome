import SwiftUI
import WebKit

struct DromeWebView: UIViewRepresentable {
    let tab: BrowserTab
    let devToolsVM: DeveloperToolsViewModel
    @EnvironmentObject var browserVM: BrowserViewModel

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(tab: tab, devToolsVM: devToolsVM, browserVM: browserVM)
    }

    func makeUIView(context: Context) -> WKWebView {
        if let existing = tab.webView {
            return existing
        }

        let config = makeConfiguration(coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isInspectable = true // Enables Safari Web Inspector (iOS 16.4+)

        applySettings(webView, coordinator: context.coordinator)

        Task { @MainActor in
            tab.webView = webView
            if let url = tab.url {
                webView.load(URLRequest(url: url))
            }
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        applySettings(webView, coordinator: context.coordinator)

        // Dark mode injection
        if browserVM.forceDarkMode {
            webView.evaluateJavaScript(
                "if (!document.getElementById('__drome_dark')) { \(JavaScriptInjector.makeBridgeScript().source) }",
                completionHandler: nil
            )
        }
    }

    private func makeConfiguration(coordinator: WebViewCoordinator) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()

        // Register message handlers
        ucc.add(coordinator, name: "dromeConsole")
        ucc.add(coordinator, name: "dromeNetwork")
        ucc.add(coordinator, name: "dromeAIFilter")
        ucc.add(coordinator, name: "dromeMutation")

        // Inject bridge at document start
        ucc.addUserScript(WKUserScript(
            source: loadJS("drome-bridge"),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        // Inject readability at document end
        ucc.addUserScript(WKUserScript(
            source: loadJS("drome-readability"),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        config.userContentController = ucc
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Apply ad blocking if enabled
        if browserVM.adBlockEnabled {
            Task {
                if let ruleList = try? await ContentBlocker.shared.ruleList() {
                    await MainActor.run {
                        config.userContentController.add(ruleList)
                    }
                }
            }
        }

        return config
    }

    private func applySettings(_ webView: WKWebView, coordinator: WebViewCoordinator) {
        let prefs = webView.configuration.preferences
        prefs.javaScriptCanOpenWindowsAutomatically = !browserVM.blockPopups

        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = browserVM.jsEnabled

        if !browserVM.customUserAgent.isEmpty {
            webView.customUserAgent = browserVM.customUserAgent
        }
    }

    private func loadJS(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url) else {
            return ""
        }
        return source
    }
}
