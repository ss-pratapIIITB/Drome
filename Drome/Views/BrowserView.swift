import SwiftUI
import WebKit

struct BrowserView: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @ObservedObject var devToolsVM: DeveloperToolsViewModel
    @State private var devToolsDragHeight: CGFloat = 300

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                AddressBarView()

                FilterStatusBar(
                    devToolsVM: devToolsVM,
                    isEnabled: browserVM.aiFilterEnabled,
                    hideUnsafe: browserVM.aiRemoveUnsafe
                ) {
                    browserVM.showAIReview = true
                }

                ZStack {
                    if let tab = browserVM.currentTab {
                        BrowserTabContent(tab: tab, devToolsVM: devToolsVM)
                    } else {
                        NewTabView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if browserVM.showDevTools {
                    Divider()
                    DeveloperToolsView(devToolsVM: devToolsVM)
                        .frame(height: devToolsHeight(for: geometry.size.height))
                        .background(Color(uiColor: .secondarySystemBackground))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    devToolsDragHeight = max(140, devToolsDragHeight - value.translation.height)
                                }
                        )
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomToolbarView(devToolsVM: devToolsVM)
                    .background(.bar, ignoresSafeAreaEdges: .bottom)
            }
        }
    }

    private func devToolsHeight(for availableHeight: CGFloat) -> CGFloat {
        max(140, min(devToolsDragHeight, availableHeight * 0.58))
    }
}

private struct BrowserTabContent: View {
    @ObservedObject var tab: BrowserTab
    let devToolsVM: DeveloperToolsViewModel

    var body: some View {
        if tab.url != nil {
            DromeWebView(tab: tab, devToolsVM: devToolsVM)
                .id(tab.id)
        } else {
            NewTabView()
        }
    }
}
