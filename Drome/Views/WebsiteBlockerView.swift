import SwiftUI

struct WebsiteBlockerView: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @Environment(\.dismiss) var dismiss
    @State private var newDomain = ""
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($browserVM.blockedDomains) { $rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.pattern)
                                    .font(.system(size: 14))
                                    .strikethrough(!rule.isEnabled, color: .secondary)
                                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                                if rule.hitCount > 0 {
                                    Text("Blocked \(rule.hitCount) time\(rule.hitCount == 1 ? "" : "s")")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: $rule.isEnabled)
                                .labelsHidden()
                                .onChange(of: rule.isEnabled) { _ in
                                    browserVM.toggleBlockedDomain(rule)
                                }
                        }
                    }
                    .onDelete { offsets in
                        browserVM.removeBlockedDomain(at: offsets)
                    }
                } header: {
                    Text("Blocked Sites")
                } footer: {
                    Text("Entire domains and their subdomains will be blocked.")
                }
            }
            .navigationTitle("Website Blocker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if browserVM.blockedDomains.isEmpty {
                    ContentUnavailableView(
                        "No Blocked Sites",
                        systemImage: "minus.circle",
                        description: Text("Tap + to block a website.")
                    )
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddBlockRuleSheet(isPresented: $showAddSheet)
            }
        }
    }
}

struct AddBlockRuleSheet: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @Binding var isPresented: Bool
    @State private var domain = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("example.com", text: $domain)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                } header: {
                    Text("Domain to block")
                } footer: {
                    Text("Enter the domain without 'https://' or 'www.'. Subdomains are automatically blocked.")
                }
            }
            .navigationTitle("Add Block Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let cleaned = domain
                            .replacingOccurrences(of: "https://", with: "")
                            .replacingOccurrences(of: "http://", with: "")
                            .replacingOccurrences(of: "www.", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleaned.isEmpty else { return }
                        browserVM.addBlockedDomain(cleaned)
                        isPresented = false
                    }
                    .disabled(domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}
