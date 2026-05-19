import SwiftUI

struct ContentView: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @StateObject var devToolsVM = DeveloperToolsViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            BrowserView(devToolsVM: devToolsVM)
                .ignoresSafeArea(edges: .bottom)

            if browserVM.showTabGrid {
                TabGridView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: browserVM.showTabGrid)
        .sheet(isPresented: $browserVM.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $browserVM.showWebsiteBlocker) {
            WebsiteBlockerView()
        }
        .sheet(isPresented: $browserVM.showDownloads) {
            DownloadsView()
        }
        .environmentObject(devToolsVM)
    }
}
