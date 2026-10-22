import SwiftUI

struct ContentView: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @StateObject var devToolsVM = DeveloperToolsViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            BrowserView(devToolsVM: devToolsVM)

            if browserVM.showTabGrid {
                TabGridView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: browserVM.showTabGrid)
        .onChange(of: browserVM.showTabGrid) { _, isShown in
            if isShown {
                browserVM.captureTabSnapshots()
            }
        }
        .sheet(isPresented: $browserVM.showAIReview) {
            AIReviewView(devToolsVM: devToolsVM)
                .environmentObject(browserVM)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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
