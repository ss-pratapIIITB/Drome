import SwiftUI
import WebKit

struct DromeWebView: UIViewRepresentable {
    let tab: BrowserTab
    let devToolsVM: DeveloperToolsViewModel
    @EnvironmentObject var browserVM: BrowserViewModel

    func makeCoordinator() -> WebViewCoordinator {
        if let coordinator = tab.webViewCoordinator { return coordinator }
        let coordinator = WebViewCoordinator(tab: tab, devToolsVM: devToolsVM, browserVM: browserVM)
        tab.webViewCoordinator = coordinator
        return coordinator
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
            // Do not start the first request until the default-on blocker is ready.
            await context.coordinator.configureAdBlocking(
                enabled: browserVM.adBlockEnabled,
                on: webView
            )
            if let url = tab.url {
                webView.load(URLRequest(url: url))
            }
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        applySettings(webView, coordinator: context.coordinator)

        context.coordinator.updatePageActivity(
            isActive: browserVM.currentTab?.id == tab.id,
            filteringEnabled: browserVM.aiFilterEnabled,
            showMarkers: browserVM.aiShowScanMarkers,
            hideUnsafe: browserVM.aiRemoveUnsafe,
            webView: webView
        )

        let adBlockingEnabled = browserVM.adBlockEnabled
        Task { @MainActor in
            let changed = await context.coordinator.configureAdBlocking(
                enabled: adBlockingEnabled,
                on: webView
            )
            if changed, webView.url != nil {
                webView.reload()
            }
        }

        context.coordinator.applyDarkMode(browserVM.forceDarkMode, on: webView)
    }

    private func makeConfiguration(coordinator: WebViewCoordinator) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()

        // Register message handlers
        ucc.add(coordinator, name: "dromeConsole")
        ucc.add(coordinator, name: "dromeNetwork")
        ucc.add(coordinator, name: "dromeAIFilter")
        ucc.add(coordinator, name: "dromeMutation")

        // Inject bridge at document start. Main-frame only keeps iframe-heavy
        // pages from paying the interception cost.
        ucc.addUserScript(WKUserScript(
            source: loadJS("drome-bridge"),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        // Shared extraction helpers used by the initial scan and mutation observer.
        ucc.addUserScript(WKUserScript(
            source: loadJS("drome-extract"),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        config.userContentController = ucc
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        return config
    }

    private func applySettings(_ webView: WKWebView, coordinator: WebViewCoordinator) {
        let prefs = webView.configuration.preferences
        prefs.javaScriptCanOpenWindowsAutomatically = !browserVM.blockPopups

        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = browserVM.jsEnabled

        webView.customUserAgent = browserVM.customUserAgent.isEmpty
            ? nil
            : browserVM.customUserAgent
    }

    private func loadJS(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return source
    }
}
