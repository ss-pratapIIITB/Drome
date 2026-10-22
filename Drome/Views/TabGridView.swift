import SwiftUI

struct TabGridView: View {
    @EnvironmentObject var browserVM: BrowserViewModel

    var body: some View {
        GeometryReader { geometry in
            let margin = DromeLayout.margin(for: geometry.size.width)

            VStack(spacing: 0) {
                header(margin: margin)

                ScrollView {
                    LazyVGrid(columns: columns(for: geometry.size.width), spacing: 14) {
                        ForEach(Array(browserVM.tabs.enumerated()), id: \.element.id) { index, tab in
                            TabCardView(tab: tab, isSelected: index == browserVM.currentTabIndex) {
                                browserVM.selectTab(index)
                            } onClose: {
                                browserVM.closeTab(at: index)
                            }
                        }
                    }
                    .padding(.horizontal, margin)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar(margin: margin)
                    .background(.bar, ignoresSafeAreaEdges: .bottom)
            }
        }
    }

    private func header(margin: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tabs")
                .font(.largeTitle.bold())

            Spacer(minLength: 12)

            Text("\(browserVM.tabs.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(browserVM.tabs.count) open tabs")

            Button("Done") {
                withAnimation { browserVM.showTabGrid = false }
            }
            .font(.body.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, margin)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func actionBar(margin: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                browserVM.addNewTab()
            } label: {
                Label("New Tab", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                browserVM.duplicateTab()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal, margin)
        .padding(.vertical, 10)
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        let margin = DromeLayout.margin(for: width)
        let available = max(0, width - 2 * margin)
        let minimum: CGFloat = width < 430 ? 150 : 170
        let count = max(2, min(5, Int(available / (minimum + 14))))
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }
}

struct TabCardView: View {
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color(uiColor: .tertiarySystemBackground)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay {
                        if let snapshot = tab.snapshot {
                            Image(uiImage: snapshot)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "globe")
                                .font(.title)
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onSelect)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(tab.displayTitle)
                    .accessibilityHint("Opens this tab")

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tab")
            }

            HStack(spacing: 6) {
                if let favicon = tab.favicon {
                    Image(uiImage: favicon)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }

                Text(tab.displayTitle)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .background(Color(uiColor: .secondarySystemBackground))
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
        }
        .clipShape(RoundedRectangle(cornerRadius: DromeLayout.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DromeLayout.cardCorner, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .contextMenu {
            Button(role: .destructive, action: onClose) {
                Label("Close Tab", systemImage: "xmark")
            }
        }
    }
}
