import SwiftUI
import WebKit

struct DeveloperToolsView: View {
    @ObservedObject var devToolsVM: DeveloperToolsViewModel
    @EnvironmentObject var browserVM: BrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            tabSelector
            Divider()
            tabContent
            Divider()
            jsEvalBar
        }
    }

    var dragHandle: some View {
        HStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 36, height: 5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(DevToolsTab.allCases, id: \.self) { tab in
                    Button {
                        devToolsVM.selectedTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(devToolsVM.selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(devToolsVM.selectedTab == tab ? Color.accentColor : Color.secondary)
                    }
                }
                Spacer()
                Button(action: devToolsVM.clearAll) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 12)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    var tabContent: some View {
        switch devToolsVM.selectedTab {
        case .console:  ConsoleView(devToolsVM: devToolsVM)
        case .network:  NetworkView(devToolsVM: devToolsVM)
        case .elements: ElementsView(devToolsVM: devToolsVM)
        case .storage:  StorageView(devToolsVM: devToolsVM)
        case .cookies:  CookiesView(devToolsVM: devToolsVM)
        case .ai:       AIDevView(devToolsVM: devToolsVM)
        }
    }

    var jsEvalBar: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
            TextField("Evaluate JavaScript...", text: $devToolsVM.jsInputText)
                .font(.system(size: 13, design: .monospaced))
                .submitLabel(.go)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { evaluateJS() }
            if !devToolsVM.jsInputText.isEmpty {
                Button { evaluateJS() } label: {
                    Image(systemName: "return")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    func evaluateJS() {
        guard !devToolsVM.jsInputText.isEmpty else { return }
        let code = devToolsVM.jsInputText
        devToolsVM.jsInputText = ""
        browserVM.currentTab?.webView?.evaluateJavaScript(code) { result, error in
            let msg: String
            if let err = error {
                msg = "Error: \(err.localizedDescription)"
            } else if let r = result {
                msg = "\(r)"
            } else {
                msg = "undefined"
            }
            Task { @MainActor in
                let entry = ConsoleEntry(
                    level: error != nil ? .error : .log,
                    message: msg,
                    source: "eval",
                    line: nil, column: nil,
                    timestamp: .now,
                    tabID: browserVM.currentTab?.id ?? UUID()
                )
                devToolsVM.addConsoleEntry(entry)
            }
        }
    }
}

// MARK: - Console

struct ConsoleView: View {
    @ObservedObject var devToolsVM: DeveloperToolsViewModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(devToolsVM.filteredConsole) { entry in
                            ConsoleEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .onChange(of: devToolsVM.filteredConsole.count) { _ in
                    if let last = devToolsVM.filteredConsole.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    var filterBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Filter", text: $devToolsVM.filterText)
                    .font(.system(size: 12))
                    .autocorrectionDisabled()
            }
            .padding(6)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 6))

            ForEach(ConsoleLevel.allCases, id: \.self) { level in
                Button {
                    if devToolsVM.selectedLevels.contains(level) {
                        devToolsVM.selectedLevels.remove(level)
                    } else {
                        devToolsVM.selectedLevels.insert(level)
                    }
                } label: {
                    Text(level.rawValue.prefix(1).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(devToolsVM.selectedLevels.contains(level) ? levelColor(level).opacity(0.2) : .clear,
                                    in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(devToolsVM.selectedLevels.contains(level) ? levelColor(level) : Color(uiColor: .quaternaryLabel))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    func levelColor(_ level: ConsoleLevel) -> Color {
        switch level {
        case .error: return .red
        case .warn: return .orange
        case .info: return .blue
        default: return .primary
        }
    }
}

struct ConsoleEntryRow: View {
    let entry: ConsoleEntry

    var levelColor: Color {
        switch entry.level {
        case .error: return .red
        case .warn: return .orange
        case .info: return .blue
        default: return .primary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 80, alignment: .leading)

            Image(systemName: entry.level.icon)
                .font(.system(size: 10))
                .foregroundStyle(levelColor)
                .frame(width: 14)

            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(entry.level == .error ? .red : entry.level == .warn ? .orange : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(entry.level == .error ? Color.red.opacity(0.05) : .clear)
        Divider().padding(.leading, 8)
    }
}

// MARK: - Network

struct NetworkView: View {
    @ObservedObject var devToolsVM: DeveloperToolsViewModel
    @State private var selectedEntry: NetworkEntry?

    var body: some View {
        if let selected = selectedEntry {
            NetworkDetailView(entry: selected) {
                selectedEntry = nil
            }
        } else {
            VStack(spacing: 0) {
                networkFilterBar
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(devToolsVM.filteredNetwork.reversed()) { entry in
                            NetworkEntryRow(entry: entry)
                                .onTapGesture { selectedEntry = entry }
                        }
                    }
                }
            }
        }
    }

    var networkFilterBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
            TextField("Filter URLs", text: $devToolsVM.filterText)
                .font(.system(size: 12))
                .autocorrectionDisabled()
            Text("\(devToolsVM.filteredNetwork.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct NetworkEntryRow: View {
    let entry: NetworkEntry

    var statusColor: Color {
        switch entry.status {
        case .pending: return .secondary
        case .success(let c): return c < 400 ? .green : .orange
        case .failure: return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.method)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, alignment: .leading)

            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayURL)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(URL(string: entry.url)?.host ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1) {
                Text(entry.sizeString)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(entry.durationString)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        Divider().padding(.leading, 8)
    }
}

struct NetworkDetailView: View {
    let entry: NetworkEntry
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 8)

                Group {
                    DetailSection("General") {
                        DetailRow("URL", entry.url)
                        DetailRow("Method", entry.method)
                        if let code = entry.status.code { DetailRow("Status", "\(code)") }
                        if let d = entry.durationString as String? { DetailRow("Duration", d) }
                        DetailRow("Size", entry.sizeString)
                        DetailRow("Type", entry.type.rawValue)
                    }

                    if !entry.requestHeaders.isEmpty {
                        DetailSection("Request Headers") {
                            ForEach(entry.requestHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                                DetailRow(kv.key, kv.value)
                            }
                        }
                    }

                    if let body = entry.requestBody {
                        DetailSection("Request Body") {
                            Text(body)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                        }
                    }

                    if let body = entry.responseBody {
                        DetailSection("Response Body") {
                            Text(body)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                        }
                    }
                }
            }
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            content
        }
    }
}

struct DetailRow: View {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        Divider().padding(.leading, 108)
    }
}

// MARK: - Elements

struct ElementsView: View {
    @ObservedObject var devToolsVM: DeveloperToolsViewModel
    @EnvironmentObject var browserVM: BrowserViewModel

    var body: some View {
        VStack {
            Button("Inspect DOM") {
                inspectDOM()
            }
            .buttonStyle(.borderedProminent)
            .padding()

            if let root = devToolsVM.domTree {
                ScrollView([.horizontal, .vertical]) {
                    DOMNodeView(node: root)
                        .padding()
                }
            } else {
                Text("Tap 'Inspect DOM' to load the element tree")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .padding()
            }
        }
    }

    func inspectDOM() {
        let js = """
        (function() {
            function nodeToObj(el, depth) {
                if (depth > 5 || !el) return null;
                const attrs = {};
                for (let a of (el.attributes || [])) attrs[a.name] = a.value;
                const children = Array.from(el.children || [])
                    .slice(0, 20)
                    .map(c => nodeToObj(c, depth + 1))
                    .filter(Boolean);
                return {
                    tag: el.tagName || el.nodeName,
                    attrs: attrs,
                    text: el.childNodes.length === 1 && el.firstChild.nodeType === 3
                        ? el.firstChild.textContent.trim().slice(0, 100) : null,
                    children: children
                };
            }
            return JSON.stringify(nodeToObj(document.body, 0));
        })()
        """
        browserVM.currentTab?.webView?.evaluateJavaScript(js) { result, _ in
            guard let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            Task { @MainActor in
                devToolsVM.domTree = parseDOMNode(obj)
            }
        }
    }

    private func parseDOMNode(_ obj: [String: Any]) -> DOMNode {
        let tag = obj["tag"] as? String ?? "?"
        let attrs = obj["attrs"] as? [String: String] ?? [:]
        let text = obj["text"] as? String
        let childObjs = obj["children"] as? [[String: Any]] ?? []
        let children = childObjs.map { parseDOMNode($0) }
        return DOMNode(tagName: tag, attributes: attrs, children: children, textContent: text)
    }
}

struct DOMNodeView: View {
    let node: DOMNode
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if !node.children.isEmpty {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .onTapGesture { expanded.toggle() }
                } else {
                    Spacer().frame(width: 13)
                }
                Text(node.displayLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .textSelection(.enabled)
                if let text = node.textContent, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if expanded && !node.children.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(node.children) { child in
                        DOMNodeView(node: child)
                    }
                }
                .padding(.leading, 16)
            }
        }
    }
}

// MARK: - Storage

struct StorageView: View {
    @ObservedObject var devToolsVM: DeveloperToolsViewModel
    @EnvironmentObject var browserVM: BrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            Button("Load Storage") { loadStorage() }
                .buttonStyle(.bordered)
                .padding(8)
            Divider()
            if devToolsVM.storageItems.isEmpty {
                Text("No storage items loaded").foregroundStyle(.secondary).padding()
            } else {
                List(devToolsVM.storageItems) { item in
                    VStack(alignment: .leading) {
                        Text(item.key).font(.system(size: 12, weight: .semibold))
                        Text(item.value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    func loadStorage() {
        let js = """
        (function() {
            const items = [];
            for (let i = 0; i < localStorage.length; i++) {
                const k = localStorage.key(i);
                items.push({key: k, value: localStorage.getItem(k), type: 'localStorage'});
            }
            for (let i = 0; i < sessionStorage.length; i++) {
                const k = sessionStorage.key(i);
                items.push({key: k, value: sessionStorage.getItem(k), type: 'sessionStorage'});
            }
            return JSON.stringify(items);
        })()
        """
        browserVM.currentTab?.webView?.evaluateJavaScript(js) { result, _ in
            guard let str = result as? String,
                  let data = str.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
            else { return }
            Task { @MainActor in
                devToolsVM.storageItems = arr.map {
                    StorageItem(key: $0["key"] ?? "", value: $0["value"] ?? "", type: $0["type"] ?? "")
                }
            }
        }
    }
}

// MARK: - Cookies

struct CookiesView: View {
    @ObservedObject var devToolsVM: DeveloperToolsViewModel
    @EnvironmentObject var browserVM: BrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            Button("Load Cookies") { loadCookies() }
                .buttonStyle(.bordered)
                .padding(8)
            Divider()
            if devToolsVM.cookieItems.isEmpty {
                Text("No cookies loaded").foregroundStyle(.secondary).padding()
            } else {
                List(devToolsVM.cookieItems) { cookie in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cookie.name).font(.system(size: 12, weight: .semibold))
                        Text(cookie.value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                        HStack {
                            Text(cookie.domain).font(.system(size: 10)).foregroundStyle(.tertiary)
                            if cookie.isSecure { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.green) }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    func loadCookies() {
        guard let webView = browserVM.currentTab?.webView else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            Task { @MainActor in
                devToolsVM.cookieItems = cookies.map { c in
                    CookieItem(
                        name: c.name, value: c.value, domain: c.domain,
                        path: c.path, expires: c.expiresDate,
                        isSecure: c.isSecure, isHTTPOnly: c.isHTTPOnly
                    )
                }
            }
        }
    }
}

// MARK: - AI Tab

struct AIDevView: View {
    @ObservedObject var devToolsVM: DeveloperToolsViewModel
    @State private var showChat = false

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control
            Picker("", selection: $showChat) {
                Text("Analysis").tag(false)
                Text("Chat").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            if showChat {
                AIChatView(devToolsVM: devToolsVM)
            } else {
                AIAnalysisView(devToolsVM: devToolsVM)
            }
        }
    }
}

struct AIAnalysisView: View {
    @ObservedObject var devToolsVM: DeveloperToolsViewModel

    var safeCount: Int { devToolsVM.aiResults.filter { $0.isSafe }.count }
    var unsafeCount: Int { devToolsVM.aiResults.filter { !$0.isSafe }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack(spacing: 12) {
                if devToolsVM.aiIsAnalyzing {
                    ProgressView().scaleEffect(0.7)
                    Text("Analyzing \(devToolsVM.aiAnalyzedCount)/\(devToolsVM.aiTotalCount) blocks…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if devToolsVM.aiResults.isEmpty {
                    Text("Enable AI Filter in Settings, then load a page.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Label("\(safeCount) safe", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                    Label("\(unsafeCount) unsafe", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                    Spacer()
                    Text("\(devToolsVM.aiResults.count) total")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(uiColor: .tertiarySystemBackground))

            Divider()

            if devToolsVM.aiResults.isEmpty && !devToolsVM.aiIsAnalyzing {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 6)
                Text("No results yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(devToolsVM.aiResults.reversed()) { result in
                            AIResultRow(result: result)
                        }
                    }
                }
            }
        }
    }
}

struct AIResultRow: View {
    let result: AIResult

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: result.isSafe ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(result.isSafe ? Color.green : Color.red)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.preview.isEmpty ? "(no preview)" : result.preview)
                    .font(.system(size: 11, design: .default))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(result.reason)
                    .font(.system(size: 10))
                    .foregroundStyle(result.isSafe ? Color.green : Color.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(result.isSafe ? Color.green.opacity(0.04) : Color.red.opacity(0.05))
        Divider().padding(.leading, 36)
    }
}

struct AIChatView: View {
    @ObservedObject var devToolsVM: DeveloperToolsViewModel
    @State private var aiFilter = AIContentFilter()
    @State private var isResponding = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if devToolsVM.aiChatMessages.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.accentColor.opacity(0.6))
                                Text("Ask me anything about this page or Drome's features.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                        }
                        ForEach(devToolsVM.aiChatMessages) { msg in
                            AIChatBubble(message: msg)
                                .id(msg.id)
                        }
                        if isResponding {
                            HStack(spacing: 4) {
                                ForEach(0..<3) { i in
                                    Circle()
                                        .fill(Color.secondary)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: devToolsVM.aiChatMessages.count) { _ in
                    if let last = devToolsVM.aiChatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Ask Drome AI…", text: $devToolsVM.aiChatInput)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(devToolsVM.aiChatInput.isEmpty ? Color.secondary : Color.accentColor)
                }
                .disabled(devToolsVM.aiChatInput.isEmpty || isResponding)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    func sendMessage() {
        let text = devToolsVM.aiChatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        devToolsVM.aiChatInput = ""
        devToolsVM.aiChatMessages.append(AIChatMessage(isUser: true, content: text))
        isResponding = true

        Task {
            let response = await aiFilter.chat(message: text)
            await MainActor.run {
                devToolsVM.aiChatMessages.append(AIChatMessage(isUser: false, content: response))
                isResponding = false
            }
        }
    }
}

struct AIChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            Text(message.content)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(message.isUser ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(message.isUser ? Color.white : Color.primary)
            if !message.isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 10)
    }
}
