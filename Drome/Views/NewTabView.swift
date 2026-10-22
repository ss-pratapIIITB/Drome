import SwiftUI

struct NewTabView: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @FocusState private var searchFocused: Bool
    @State private var searchText = ""

    private var isShort: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: isShort ? 14 : 22) {
                        Spacer(minLength: isShort ? 16 : 32)

                        Image(systemName: "globe")
                            .font(.system(size: isShort ? 40 : 58, weight: .light))
                            .foregroundStyle(.quaternary)

                        Text("Drome")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.secondary)

                        searchField
                            .frame(maxWidth: DromeLayout.searchMaxWidth)
                            .id("new-tab-search")

                        Text("A quieter way to browse.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)

                        Spacer(minLength: isShort ? 16 : 32)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                    .padding(.horizontal, DromeLayout.margin(for: geometry.size.width))
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: searchFocused) { _, focused in
                    guard focused else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("new-tab-search", anchor: .center)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)

            TextField("Search or enter URL", text: $searchText)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($searchFocused)
                .onSubmit(submit)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: DromeLayout.cardCorner, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DromeLayout.cardCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func submit() {
        let value = searchText
        searchText = ""
        searchFocused = false
        browserVM.navigate(to: value)
    }
}
