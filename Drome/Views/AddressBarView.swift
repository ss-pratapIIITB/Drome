import SwiftUI

struct AddressBarView: View {
    @EnvironmentObject var browserVM: BrowserViewModel

    var body: some View {
        if let tab = browserVM.currentTab {
            AddressBarContent(tab: tab)
                .id(tab.id)
        }
    }
}

private struct AddressBarContent: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @ObservedObject var tab: BrowserTab

    @FocusState private var fieldFocused: Bool
    @State private var isEditing = false
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                securityIndicator

                addressField
                    .frame(maxWidth: .infinity)

                trailingControls
            }
            .padding(.horizontal, DromeLayout.screenMargin)
            .padding(.vertical, 6)

            if tab.isLoading {
                progressBar
            } else {
                Divider()
            }
        }
        .background(.bar, ignoresSafeAreaEdges: .top)
        .onChange(of: isEditing) { _, editing in
            if editing {
                Task { @MainActor in
                    fieldFocused = true
                }
            } else {
                fieldFocused = false
            }
        }
        .onChange(of: fieldFocused) { _, focused in
            if !focused, isEditing {
                isEditing = false
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    commitEditing()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.accentColor)
                .frame(
                    width: geometry.size.width * max(0, min(1, tab.estimatedProgress)),
                    height: 2
                )
                .animation(.linear(duration: 0.1), value: tab.estimatedProgress)
        }
        .frame(height: 2)
    }

    private var securityIndicator: some View {
        let isSecure = tab.url?.scheme == "https"
        let isLocal = tab.url?.scheme == "file" || tab.url?.scheme == "about"
        return Image(systemName: isLocal ? "doc" : (isSecure ? "lock.fill" : "lock.open"))
            .font(.caption)
            .foregroundStyle(isSecure ? .green : (isLocal ? .secondary : .orange))
            .frame(width: 20)
            .accessibilityLabel(isSecure ? "Secure connection" : "Connection not secure")
    }

    private var addressField: some View {
        Group {
            if isEditing {
                HStack(spacing: 6) {
                    TextField("Search or enter URL", text: $inputText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .font(.subheadline)
                        .focused($fieldFocused)
                        .onSubmit(commitEditing)

                    if !inputText.isEmpty {
                        Button {
                            inputText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear address")
                    }
                }
            } else {
                Button {
                    beginEditing()
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.displayTitle)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Address or page title")
                .accessibilityValue(tab.displayTitle)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: DromeLayout.addressBarMinHeight)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: DromeLayout.controlCorner, style: .continuous)
        )
    }

    private var trailingControls: some View {
        HStack(spacing: 2) {
            if isEditing {
                Button {
                    isEditing = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel editing")
            } else if tab.isLoading {
                Button {
                    browserVM.stopLoading()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop loading")
            } else {
                Button {
                    browserVM.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reload page")
                .contextMenu {
                    Button("Hard Reload") { browserVM.hardReload() }
                    Button("Copy URL") { browserVM.copyCurrentURL() }
                }
            }
        }
    }

    private func beginEditing() {
        inputText = tab.displayURL
        isEditing = true
    }

    private func commitEditing() {
        guard isEditing else {
            fieldFocused = false
            return
        }
        let text = inputText
        isEditing = false
        fieldFocused = false
        browserVM.navigate(to: text)
    }
}
