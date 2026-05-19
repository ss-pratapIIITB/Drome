import SwiftUI

struct TabGridView: View {
    @EnvironmentObject var browserVM: BrowserViewModel

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("\(browserVM.tabs.count) Tab\(browserVM.tabs.count == 1 ? "" : "s")")
                        .font(.headline)
                    Spacer()
                    Button("Done") {
                        withAnimation { browserVM.showTabGrid = false }
                    }
                    .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(browserVM.tabs.enumerated()), id: \.element.id) { index, tab in
                            TabCardView(tab: tab, isSelected: index == browserVM.currentTabIndex) {
                                browserVM.selectTab(index)
                            } onClose: {
                                browserVM.closeTab(at: index)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 80)
                }
            }

            HStack(spacing: 20) {
                Button {
                    browserVM.addNewTab()
                } label: {
                    Label("New Tab", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }

                Button {
                    browserVM.duplicateTab()
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
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
                Group {
                    if let snapshot = tab.snapshot {
                        Image(uiImage: snapshot)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color(uiColor: .tertiarySystemBackground))
                            .overlay {
                                Image(systemName: "globe")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.quaternary)
                            }
                    }
                }
                .frame(height: 140)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .padding(6)
            }

            HStack {
                if let favicon = tab.favicon {
                    Image(uiImage: favicon)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(tab.displayTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}
