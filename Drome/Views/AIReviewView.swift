import SwiftUI

struct AIReviewView: View {
    @ObservedObject var devToolsVM: DeveloperToolsViewModel
    @EnvironmentObject var browserVM: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    private var flagged: [AIResult] {
        devToolsVM.aiResults.filter { !$0.isSafe }
    }

    private var safe: [AIResult] {
        devToolsVM.aiResults.filter(\.isSafe)
    }

    private var checked: Int {
        devToolsVM.aiResults.count
    }

    private var total: Int {
        max(devToolsVM.aiTotalCount, checked)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !browserVM.aiFilterEnabled {
                    filterOffView
                } else if checked == 0, !devToolsVM.aiIsAnalyzing {
                    emptyView
                } else {
                    reviewList
                }
            }
            .navigationTitle("Page review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var reviewList: some View {
        List {
            Section {
                summary
            }

            if !flagged.isEmpty {
                Section("Flagged") {
                    ForEach(flagged) { result in
                        resultRow(result, isFlagged: true)
                    }
                }
            }

            if !safe.isEmpty {
                Section("Reviewed safe") {
                    ForEach(safe) { result in
                        resultRow(result, isFlagged: false)
                    }
                }
            }

            Section {
                Toggle("Hide flagged content", isOn: $browserVM.aiRemoveUnsafe)
                    .onChange(of: browserVM.aiRemoveUnsafe) { _, _ in
                        browserVM.applyAISettingsToCurrentPage()
                    }
                Toggle("Show scan markers", isOn: $browserVM.aiShowScanMarkers)
                    .onChange(of: browserVM.aiShowScanMarkers) { _, _ in
                        browserVM.applyAISettingsToCurrentPage()
                    }
            } footer: {
                Text("With markers off, flagged content simply disappears. Markers add the green/red debug boxes around every scanned block for review.")
            }

            Section {
                DisclosureGroup("Advanced details") {
                    Text("Decisions are made on-device with Laya MLX. Keyword rules remain the fallback when the model is unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(flagged) { result in
                        Text(result.xpath)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: devToolsVM.aiIsAnalyzing ? "shield.lefthalf.filled" : (flagged.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill"))
                .font(.title2)
                .foregroundStyle(devToolsVM.aiIsAnalyzing ? Color.accentColor : (flagged.isEmpty ? .green : .red))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(summaryTitle)
                    .font(.headline)
                Text(summaryDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var summaryTitle: String {
        if devToolsVM.aiIsAnalyzing {
            return "Scanning this page"
        }
        if flagged.isEmpty {
            return "No flagged blocks"
        }
        return "\(flagged.count) flagged \(flagged.count == 1 ? "block" : "blocks")"
    }

    private var summaryDetail: String {
        if devToolsVM.aiIsAnalyzing {
            return "\(checked) of \(total) blocks checked"
        }
        return "\(checked) of \(total) blocks checked · \(safe.count) safe"
    }

    private func resultRow(_ result: AIResult, isFlagged: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isFlagged ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(isFlagged ? .red : .green)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.preview.isEmpty ? "Text block" : result.preview)
                    .font(.subheadline)
                    .lineLimit(3)

                Text(result.reason)
                    .font(.caption)
                    .foregroundStyle(isFlagged ? .red : .secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var filterOffView: some View {
        ContentUnavailableView {
            Label("Filter is off", systemImage: "shield.slash")
        } description: {
            Text("Turn on the AI Content Filter to review this page on-device.")
        } actions: {
            Button("Open Settings") {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No page scan yet", systemImage: "shield")
        } description: {
            Text("Open a page and Drome will review qualifying text blocks automatically.")
        }
    }

    private func openSettings() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            browserVM.showSettings = true
        }
    }
}
