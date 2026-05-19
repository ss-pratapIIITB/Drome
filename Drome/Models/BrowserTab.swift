import Foundation
import WebKit
import UIKit

@MainActor
final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()

    @Published var url: URL?
    @Published var title: String = "New Tab"
    @Published var favicon: UIImage?
    @Published var isLoading = false
    @Published var estimatedProgress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var snapshot: UIImage?
    @Published var errorMessage: String?

    var webView: WKWebView?

    init(url: URL? = nil) {
        self.url = url
    }

    var displayTitle: String {
        title.isEmpty ? (url?.host ?? "New Tab") : title
    }

    var displayURL: String {
        url?.absoluteString ?? ""
    }
}
