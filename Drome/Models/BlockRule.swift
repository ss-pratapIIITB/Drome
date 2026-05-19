import Foundation

enum BlockRuleType: String, Codable, CaseIterable {
    case domain = "Domain"
    case urlPattern = "URL Pattern"
    case cssSelector = "CSS Selector"
}

struct BlockRule: Identifiable, Codable {
    var id = UUID()
    var pattern: String
    var type: BlockRuleType
    var isEnabled: Bool = true
    var isBuiltIn: Bool = false
    var createdAt: Date = .now
    var hitCount: Int = 0

    var displayPattern: String {
        pattern
    }

    static func domainRule(_ domain: String, builtIn: Bool = false) -> BlockRule {
        BlockRule(pattern: domain, type: .domain, isBuiltIn: builtIn)
    }
}
