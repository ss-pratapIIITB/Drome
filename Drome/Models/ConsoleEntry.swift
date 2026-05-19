import Foundation

enum ConsoleLevel: String, CaseIterable {
    case log, info, warn, error, debug, trace

    var color: String {
        switch self {
        case .log, .debug, .trace: return "primary"
        case .info: return "blue"
        case .warn: return "orange"
        case .error: return "red"
        }
    }

    var icon: String {
        switch self {
        case .log, .trace: return "terminal"
        case .info: return "info.circle"
        case .debug: return "ant"
        case .warn: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
}

struct ConsoleEntry: Identifiable {
    let id = UUID()
    let level: ConsoleLevel
    let message: String
    let source: String
    let line: Int?
    let column: Int?
    let timestamp: Date
    let tabID: UUID

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }
}
