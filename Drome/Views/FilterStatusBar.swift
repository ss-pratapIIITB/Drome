import SwiftUI

struct FilterStatusBar: View {
    @ObservedObject var devToolsVM: DeveloperToolsViewModel
    let isEnabled: Bool
    let hideUnsafe: Bool
    let onReview: () -> Void

    private var unsafeCount: Int {
        devToolsVM.aiResults.filter { !$0.isSafe }.count
    }

    private var safeCount: Int {
        devToolsVM.aiResults.filter(\.isSafe).count
    }

    private var hasActivity: Bool {
        isEnabled && (devToolsVM.aiIsAnalyzing || devToolsVM.aiTotalCount > 0 || !devToolsVM.aiResults.isEmpty)
    }

    var body: some View {
        if hasActivity {
            Button(action: onReview) {
                HStack(spacing: 8) {
                    statusIcon
                        .frame(width: 18)

                    Text(statusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DromeLayout.screenMargin)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .background(tint.opacity(0.10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Page filter status")
            .accessibilityValue(statusText)
            .accessibilityHint("Opens page review")
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if devToolsVM.aiIsAnalyzing {
            ProgressView()
                .controlSize(.mini)
        } else if unsafeCount > 0 {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.shield.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private var statusText: String {
        if devToolsVM.aiIsAnalyzing {
            let total = max(devToolsVM.aiTotalCount, devToolsVM.aiAnalyzedCount)
            return "Scanning \(devToolsVM.aiAnalyzedCount) of \(total) blocks"
        }
        if unsafeCount > 0 {
            let action = hideUnsafe ? "hidden" : "flagged"
            return "\(unsafeCount) \(action) · \(safeCount) safe · Review"
        }
        return "All clear · \(safeCount) blocks checked"
    }

    private var tint: Color {
        if devToolsVM.aiIsAnalyzing { return .accentColor }
        return unsafeCount > 0 ? .red : .green
    }
}
