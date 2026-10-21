import SwiftUI
import WebKit

struct BrowserView: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @ObservedObject var devToolsVM: DeveloperToolsViewModel
    @State private var devToolsDragHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            AddressBarView()
                .background(.bar)

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
                    .frame(height: max(150, min(devToolsDragHeight, UIScreen.main.bounds.height * 0.6)))
                    .background(Color(uiColor: .secondarySystemBackground))
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                devToolsDragHeight -= v.translation.height
                            }
                    )
            }

            BottomToolbarView()
                .background(.bar)
        }
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

struct NewTabView: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 60))
                .foregroundStyle(.quaternary)
            Text("Drome")
                .font(.largeTitle.bold())
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search or enter URL", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit {
                        browserVM.navigate(to: searchText)
                        searchText = ""
                    }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
            Spacer()
        }
    }
}

struct BottomToolbarView: View {
    @EnvironmentObject var browserVM: BrowserViewModel

    var body: some View {
        if let tab = browserVM.currentTab {
            BottomToolbarContent(tab: tab)
        }
    }
}

private struct BottomToolbarContent: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @ObservedObject var tab: BrowserTab

    var body: some View {
        HStack(spacing: 0) {
            toolbarButton("chevron.left", enabled: tab.canGoBack) {
                browserVM.goBack()
            }
            toolbarButton("chevron.right", enabled: tab.canGoForward) {
                browserVM.goForward()
            }
            Spacer()
            toolbarButton("book.pages", active: browserVM.readingModeActive) {
                toggleReadingMode()
            }
            toolbarButton("square.on.square") {
                withAnimation { browserVM.showTabGrid.toggle() }
            }
            toolbarButton("hammer", active: browserVM.showDevTools) {
                withAnimation { browserVM.showDevTools.toggle() }
            }
            toolbarButton("ellipsis.circle") {
                browserVM.showSettings = true
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    private func toggleReadingMode() {
        tab.webView?.evaluateJavaScript(JavaScriptInjector.toggleReadingModeJS()) { result, _ in
            if let res = result as? String {
                Task { @MainActor in
                    browserVM.readingModeActive = (res == "on")
                }
            }
        }
    }

    @ViewBuilder
    func toolbarButton(_ icon: String, enabled: Bool = true, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(enabled ? Color.primary : Color(uiColor: .quaternaryLabel)))
        }
        .disabled(!enabled)
        .frame(maxWidth: .infinity)
    }
}
