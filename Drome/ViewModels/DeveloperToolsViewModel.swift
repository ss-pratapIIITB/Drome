import SwiftUI
import Combine

enum DevToolsTab: String, CaseIterable {
    case console = "Console"
    case network = "Network"
    case elements = "Elements"
    case storage = "Storage"
    case cookies = "Cookies"
    case ai = "AI"

    var icon: String {
        switch self {
        case .console:  return "terminal"
        case .network:  return "network"
        case .elements: return "curlybraces"
        case .storage:  return "internaldrive"
        case .cookies:  return "doc.text"
        case .ai:       return "sparkles"
        }
    }
}

@MainActor
final class DeveloperToolsViewModel: ObservableObject {

    @Published var selectedTab: DevToolsTab = .console
    @Published var consoleEntries: [ConsoleEntry] = []
    @Published var networkEntries: [NetworkEntry] = []
    @Published var pendingNetworkEntries: [String: NetworkEntry] = [:]
    @Published var filterText = ""
    @Published var selectedLevels: Set<ConsoleLevel> = Set(ConsoleLevel.allCases)
    @Published var selectedNetworkEntry: NetworkEntry?
    @Published var jsInputText = ""
    @Published var storageItems: [StorageItem] = []
    @Published var cookieItems: [CookieItem] = []
    @Published var domTree: DOMNode?

    // AI Analysis
    @Published var aiResults: [AIResult] = []
    @Published var aiIsAnalyzing = false
    @Published var aiAnalyzedCount = 0
    @Published var aiTotalCount = 0

    // AI Chat
    @Published var aiChatMessages: [AIChatMessage] = []
    @Published var aiChatInput = ""

    var filteredConsole: [ConsoleEntry] {
        consoleEntries.filter { entry in
            selectedLevels.contains(entry.level) &&
            (filterText.isEmpty || entry.message.localizedCaseInsensitiveContains(filterText))
        }
    }

    var filteredNetwork: [NetworkEntry] {
        networkEntries.filter { entry in
            filterText.isEmpty ||
            entry.url.localizedCaseInsensitiveContains(filterText) ||
            entry.method.localizedCaseInsensitiveContains(filterText)
        }
    }

    func addConsoleEntry(_ entry: ConsoleEntry) {
        consoleEntries.append(entry)
        if consoleEntries.count > 2000 {
            consoleEntries.removeFirst(consoleEntries.count - 2000)
        }
    }

    func addNetworkRequest(_ entry: NetworkEntry) {
        pendingNetworkEntries[entry.id] = entry
        networkEntries.append(entry)
    }

    func updateNetworkResponse(id: String, status: Int, duration: TimeInterval, size: Int) {
        if let idx = networkEntries.firstIndex(where: { $0.id == id }) {
            networkEntries[idx].status = status >= 400 ? .failure("HTTP \(status)") : .success(status)
            networkEntries[idx].duration = duration
            networkEntries[idx].responseSize = size
        }
        pendingNetworkEntries.removeValue(forKey: id)
    }

    func markNetworkError(id: String, message: String) {
        if let idx = networkEntries.firstIndex(where: { $0.id == id }) {
            networkEntries[idx].status = .failure(message)
        }
        pendingNetworkEntries.removeValue(forKey: id)
    }

    func addAIResult(_ result: AIResult) {
        aiResults.append(result)
        aiAnalyzedCount += 1
    }

    func clearAIResults() {
        aiResults.removeAll()
        aiIsAnalyzing = false
        aiAnalyzedCount = 0
        aiTotalCount = 0
    }

    func clearConsole() { consoleEntries.removeAll() }
    func clearNetwork() { networkEntries.removeAll(); pendingNetworkEntries.removeAll() }

    func clearAll() {
        clearConsole()
        clearNetwork()
        storageItems.removeAll()
        cookieItems.removeAll()
        clearAIResults()
        aiChatMessages.removeAll()
    }
}

// MARK: - AI Models

struct AIResult: Identifiable {
    let id = UUID()
    let xpath: String
    let isSafe: Bool
    let reason: String
    let preview: String
}

struct AIChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let content: String
    let timestamp: Date = .now
}

// MARK: - Other Models

struct StorageItem: Identifiable {
    let id = UUID()
    let key: String
    let value: String
    let type: String
}

struct CookieItem: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
}

struct DOMNode: Identifiable {
    let id = UUID()
    let tagName: String
    let attributes: [String: String]
    var children: [DOMNode]
    var textContent: String?
    var isExpanded = true

    var displayLabel: String {
        var label = "<\(tagName.lowercased())"
        if let cls = attributes["class"] { label += " class=\"\(cls)\"" }
        if let id = attributes["id"] { label += " id=\"\(id)\"" }
        label += ">"
        return label
    }
}
