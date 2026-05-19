import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showClearConfirm = false
    @State private var showInspectorHelp = false

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy & Security") {
                    Toggle(isOn: $browserVM.adBlockEnabled) {
                        Label("Ad Blocking", systemImage: "hand.raised.fill")
                    }
                    .onChange(of: browserVM.adBlockEnabled) { _ in
                        browserVM.reload()
                    }
                    Toggle(isOn: $browserVM.aiFilterEnabled) {
                        Label("AI Content Filter", systemImage: "sparkles.rectangle.stack")
                    }
                    .onChange(of: browserVM.aiFilterEnabled) { _ in
                        browserVM.reload()
                    }
                    if browserVM.aiFilterEnabled {
                        Toggle(isOn: $browserVM.aiRemoveUnsafe) {
                            Label("Remove Unsafe Content", systemImage: "xmark.shield")
                        }
                        .padding(.leading, 24)
                    }
                    Toggle(isOn: $browserVM.blockPopups) {
                        Label("Block Pop-ups", systemImage: "xmark.rectangle")
                    }
                    .onChange(of: browserVM.blockPopups) { _ in
                        browserVM.reload()
                    }
                    NavigationLink {
                        WebsiteBlockerView()
                    } label: {
                        Label("Website Blocker", systemImage: "minus.circle")
                    }
                }

                Section("Display") {
                    Toggle(isOn: $browserVM.forceDarkMode) {
                        Label("Force Dark Mode", systemImage: "moon.fill")
                    }
                }

                Section("Browser") {
                    Toggle(isOn: $browserVM.jsEnabled) {
                        Label("JavaScript", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .onChange(of: browserVM.jsEnabled) { _ in
                        browserVM.reload()
                    }
                    NavigationLink {
                        SearchEngineView()
                    } label: {
                        Label("Search Engine", systemImage: "magnifyingglass")
                    }
                    NavigationLink {
                        UserAgentView()
                    } label: {
                        Label("User Agent", systemImage: "desktopcomputer")
                    }
                }

                Section("Developer") {
                    Button {
                        browserVM.showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            browserVM.showDevTools = true
                        }
                    } label: {
                        Label("Open DevTools", systemImage: "hammer")
                            .foregroundStyle(.primary)
                    }
                    Button {
                        showInspectorHelp = true
                    } label: {
                        Label("Remote Web Inspector (via Safari)", systemImage: "safari")
                            .foregroundStyle(.primary)
                    }
                    Button {
                        browserVM.showDownloads = true
                        dismiss()
                    } label: {
                        Label("Downloads", systemImage: "arrow.down.circle")
                            .foregroundStyle(.primary)
                    }
                }

                Section("Data") {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear Browsing Data", systemImage: "trash")
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Engine")
                        Spacer()
                        Text("WebKit").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                        .fontWeight(.semibold)
                }
            }
            .alert("Remote Web Inspector", isPresented: $showInspectorHelp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("On your Mac, open Safari → Settings → Advanced → enable \"Show features for web developers\". Then connect iPhone via USB and go to Safari → Develop → [your iPhone] → Drome.")
            }
            .confirmationDialog("Clear Browsing Data", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear Cache", role: .destructive) {
                    clearData(types: [WKWebsiteDataTypeDiskCache,
                                      WKWebsiteDataTypeOfflineWebApplicationCache,
                                      WKWebsiteDataTypeMemoryCache])
                }
                Button("Clear Cookies", role: .destructive) {
                    clearData(types: [WKWebsiteDataTypeCookies])
                }
                Button("Clear All", role: .destructive) {
                    clearData(types: WKWebsiteDataStore.allWebsiteDataTypes())
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove data for all sites.")
            }
        }
    }

    func clearData(types: Set<String>) {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {}
        }
    }
}

struct SearchEngineView: View {
    @EnvironmentObject var browserVM: BrowserViewModel

    private let engines: [(name: String, url: String)] = [
        (name: "DuckDuckGo", url: "https://duckduckgo.com/?q="),
        (name: "Google", url: "https://google.com/search?q="),
        (name: "Bing", url: "https://bing.com/search?q="),
        (name: "Brave", url: "https://search.brave.com/search?q="),
        (name: "Ecosia", url: "https://ecosia.org/search?q="),
        (name: "Startpage", url: "https://startpage.com/search?q="),
    ]

    var body: some View {
        List {
            ForEach(engines.indices, id: \.self) { i in
                let engine = engines[i]
                Button {
                    browserVM.searchEngine = engine.url
                } label: {
                    HStack {
                        Text(engine.name).foregroundStyle(.primary)
                        Spacer()
                        if browserVM.searchEngine == engine.url {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Search Engine")
    }
}

struct UserAgentView: View {
    @EnvironmentObject var browserVM: BrowserViewModel

    private let presets: [(name: String, ua: String)] = [
        (name: "Default (Mobile Safari)", ua: ""),
        (name: "Desktop Safari", ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"),
        (name: "Desktop Chrome", ua: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"),
        (name: "Firefox", ua: "Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0"),
        (name: "Googlebot", ua: "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"),
    ]

    var body: some View {
        List {
            Section("Presets") {
                ForEach(presets.indices, id: \.self) { i in
                    let preset = presets[i]
                    Button {
                        browserVM.customUserAgent = preset.ua
                        browserVM.reload()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(preset.name).foregroundStyle(.primary)
                                if !preset.ua.isEmpty {
                                    Text(preset.ua).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer()
                            if browserVM.customUserAgent == preset.ua {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            Section("Custom") {
                TextField("Enter custom user agent", text: $browserVM.customUserAgent)
                    .font(.system(size: 13, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle("User Agent")
    }
}

struct DownloadsView: View {
    @EnvironmentObject var browserVM: BrowserViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if browserVM.downloadItems.isEmpty {
                    ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                        description: Text("Files you download will appear here."))
                } else {
                    List(browserVM.downloadItems) { item in
                        HStack {
                            Image(systemName: item.isComplete ? "doc.fill" : "arrow.down.circle")
                                .foregroundStyle(item.isComplete ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading) {
                                Text(item.filename).font(.system(size: 14))
                                if !item.isComplete {
                                    ProgressView(value: item.progress)
                                        .tint(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}
