import SwiftUI

@main
struct DromeApp: App {
    @StateObject private var browserVM = BrowserViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(browserVM)
                .preferredColorScheme(browserVM.forceDarkMode ? .dark : nil)
                .onOpenURL { url in
                    // drome://open?url=https://...
                    guard url.scheme == "drome",
                          url.host == "open",
                          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          let target = components.queryItems?.first(where: { $0.name == "url" })?.value
                    else { return }
                    browserVM.navigate(to: target)
                }
        }
    }
}
