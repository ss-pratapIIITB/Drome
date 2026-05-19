import SwiftUI

struct AddressBarView: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @State private var isEditing = false
    @State private var inputText = ""
    @State private var showMenu = false

    var tab: BrowserTab? { browserVM.currentTab }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                securityIndicator

                addressField
                    .frame(maxWidth: .infinity)

                if tab?.isLoading == true {
                    Button {
                        browserVM.stopLoading()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                } else {
                    Button {
                        browserVM.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .contextMenu {
                        Button("Hard Reload") { browserVM.hardReload() }
                        Button("Copy URL") { browserVM.copyCurrentURL() }
                    }
                }

                shareButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if let tab, tab.isLoading {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * tab.estimatedProgress, height: 2)
                        .animation(.linear(duration: 0.1), value: tab.estimatedProgress)
                }
                .frame(height: 2)
            } else {
                Divider()
            }
        }
    }

    var securityIndicator: some View {
        let isSecure = tab?.url?.scheme == "https"
        let isLocal = tab?.url?.scheme == "file" || tab?.url?.scheme == "about"
        return Image(systemName: isLocal ? "doc" : (isSecure ? "lock.fill" : "lock.open"))
            .font(.system(size: 12))
            .foregroundStyle(isSecure ? .green : (isLocal ? .secondary : .orange))
            .frame(width: 20)
    }

    var addressField: some View {
        Group {
            if isEditing {
                TextField("Search or enter URL", text: $inputText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .font(.system(size: 15))
                    .onSubmit {
                        isEditing = false
                        browserVM.navigate(to: inputText)
                    }
            } else {
                Button {
                    inputText = tab?.displayURL ?? ""
                    isEditing = true
                } label: {
                    Text(tab?.displayTitle ?? "New Tab")
                        .font(.system(size: 15))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    var shareButton: some View {
        Group {
            if let url = tab?.url {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
            }
        }
    }
}
