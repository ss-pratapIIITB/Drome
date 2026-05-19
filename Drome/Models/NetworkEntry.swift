import Foundation

enum NetworkRequestType: String {
    case fetch = "Fetch"
    case xhr = "XHR"
    case navigation = "Navigation"
    case resource = "Resource"
}

enum NetworkEntryStatus {
    case pending
    case success(Int)
    case failure(String)

    var code: Int? {
        if case .success(let c) = self { return c }
        return nil
    }

    var displayColor: String {
        switch self {
        case .pending: return "secondary"
        case .success(let c): return c < 400 ? "green" : "orange"
        case .failure: return "red"
        }
    }
}

struct NetworkEntry: Identifiable {
    let id: String
    let url: String
    let method: String
    let type: NetworkRequestType
    let startTime: Date
    var status: NetworkEntryStatus = .pending
    var duration: TimeInterval?
    var responseSize: Int?
    var requestHeaders: [String: String] = [:]
    var responseHeaders: [String: String] = [:]
    var requestBody: String?
    var responseBody: String?
    let tabID: UUID

    var displayURL: String {
        URL(string: url)?.lastPathComponent.isEmpty == false
            ? URL(string: url)?.lastPathComponent ?? url
            : url
    }

    var durationString: String {
        guard let d = duration else { return "pending" }
        return d < 1 ? "\(Int(d * 1000))ms" : String(format: "%.2fs", d)
    }

    var sizeString: String {
        guard let s = responseSize else { return "-" }
        return s < 1024 ? "\(s)B" : s < 1_048_576 ? "\(s / 1024)KB" : "\(s / 1_048_576)MB"
    }
}
