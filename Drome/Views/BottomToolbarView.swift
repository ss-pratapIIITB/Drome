import SwiftUI

struct BottomToolbarView: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @ObservedObject var devToolsVM: DeveloperToolsViewModel

    var body: some View {
        if let tab = browserVM.currentTab {
            BottomToolbarContent(tab: tab, devToolsVM: devToolsVM)
        }
    }
}

private struct BottomToolbarContent: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @ObservedObject var tab: BrowserTab
    @ObservedObject var devToolsVM: DeveloperToolsViewModel

    private var unsafeCount: Int {
        devToolsVM.aiResults.filter { !$0.isSafe }.count
    }

    private var filterIcon: String {
        if !browserVM.aiFilterEnabled { return "shield.slash" }
        if devToolsVM.aiIsAnalyzing { return "shield.lefthalf.filled" }
        return unsafeCount > 0 ? "exclamationmark.shield.fill" : "checkmark.shield"
    }

    private var filterTint: Color {
        if !browserVM.aiFilterEnabled { return .secondary }
        if unsafeCount > 0 { return .red }
        return .accentColor
    }

    var body: some View {
        HStack(spacing: 0) {
            toolbarButton("chevron.left", label: "Back", enabled: tab.canGoBack) {
                browserVM.goBack()
            }

            toolbarButton("chevron.right", label: "Forward", enabled: tab.canGoForward) {
                browserVM.goForward()
            }

            toolbarButton(
                filterIcon,
                label: "Page review",
                tint: filterTint
            ) {
                browserVM.showAIReview = true
            }

            toolbarButton("square.on.square", label: "Tabs") {
                withAnimation { browserVM.showTabGrid.toggle() }
            }

            menuButton
        }
        .padding(.horizontal, 8)
        .frame(height: DromeLayout.toolbarHeight)
    }

    private var menuButton: some View {
        Menu {
            Button {
                toggleReadingMode()
            } label: {
                Label(
                    browserVM.readingModeActive ? "Exit Reading Mode" : "Reading Mode",
                    systemImage: "book.pages"
                )
            }

            Button {
                withAnimation { browserVM.showDevTools.toggle() }
            } label: {
                Label(
                    browserVM.showDevTools ? "Hide Developer Tools" : "Developer Tools",
                    systemImage: "hammer"
                )
            }

            Button {
                browserVM.showDownloads = true
            } label: {
                Label("Downloads", systemImage: "arrow.down.circle")
            }

            Divider()

            if let url = tab.url {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                browserVM.showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }

    private func toggleReadingMode() {
        tab.webView?.evaluateJavaScript(JavaScriptInjector.toggleReadingModeJS()) { result, _ in
            if let result = result as? String {
                Task { @MainActor in
                    browserVM.readingModeActive = (result == "on")
                }
            }
        }
    }

    private func toolbarButton(
        _ icon: String,
        label: String,
        enabled: Bool = true,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(enabled ? (tint ?? .primary) : Color(uiColor: .quaternaryLabel))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
