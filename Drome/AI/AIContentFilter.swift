import Foundation

struct ContentClassificationResult {
    let isSafe: Bool
    let reason: String
    let method: String
    let confidence: Double?
    let latencyMs: Double?
}

// MARK: - AIContentFilter

final class AIContentFilter {

    private let layaRuntime = LayaMLXRuntime.shared

    // Minimum chars to bother classifying at all
    private let minBlockLength = 25

    // Keep inference small and responsive; the native runtime also enforces its own input cap.
    private let maxBlockChars = 400

    func prepareLaya() async throws {
        try await layaRuntime.prepare()
    }

    func classify(text rawText: String, useLaya: Bool) async -> ContentClassificationResult? {
        let results = await classifyBatch(texts: [rawText], useLaya: useLaya)
        guard let first = results.first else { return nil }
        return first
    }

    /// Classifies a batch in one model call. Results keep the input order and are
    /// `nil` for blocks shorter than `minBlockLength`.
    func classifyBatch(texts rawTexts: [String], useLaya: Bool) async -> [ContentClassificationResult?] {
        var cleanedTexts = [String?](repeating: nil, count: rawTexts.count)
        var results = [ContentClassificationResult?](repeating: nil, count: rawTexts.count)
        var pendingIndices: [Int] = []
        var pendingTexts: [String] = []

        for (index, rawText) in rawTexts.enumerated() {
            let cleanedText = cleanText(rawText)
            guard cleanedText.count >= minBlockLength else { continue }
            cleanedTexts[index] = cleanedText

            let (keywordSafe, keywordReason) = classifyWithHeuristics(text: cleanedText)
            if !keywordSafe {
                results[index] = ContentClassificationResult(
                    isSafe: false,
                    reason: keywordReason,
                    method: "kw",
                    confidence: nil,
                    latencyMs: nil
                )
            } else if useLaya, wordCount(cleanedText) > 3 {
                pendingIndices.append(index)
                pendingTexts.append(String(cleanedText.prefix(maxBlockChars)))
            } else {
                results[index] = ContentClassificationResult(
                    isSafe: true,
                    reason: keywordReason,
                    method: "kw",
                    confidence: nil,
                    latencyMs: nil
                )
            }
        }

        guard !pendingTexts.isEmpty else { return results }

        do {
            let responses = try await layaRuntime.classifyBatch(pendingTexts)
            for (offset, index) in pendingIndices.enumerated() where offset < responses.count {
                let response = responses[offset]
                results[index] = ContentClassificationResult(
                    isSafe: response.safe,
                    reason: response.reason,
                    method: "laya",
                    confidence: response.confidence,
                    latencyMs: response.latencyMs
                )
            }
        } catch {
            for index in pendingIndices {
                guard let cleanedText = cleanedTexts[index] else { continue }
                let (keywordSafe, keywordReason) = classifyWithHeuristics(text: cleanedText)
                results[index] = ContentClassificationResult(
                    isSafe: keywordSafe,
                    reason: keywordReason,
                    method: "kw-fallback",
                    confidence: nil,
                    latencyMs: nil
                )
            }
        }

        return results
    }

    // MARK: - Text cleaning

    private func cleanText(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { !$0.isEmpty }
            .count
    }

    // MARK: - Keyword heuristics (short blocks and Laya fallback)

    private static let highRiskKeywords: [(String, String)] = [
        ("killed", "Violence/death"), ("murder", "Violence"),
        ("shooting", "Violence"), ("bombing", "Violence"),
        ("massacre", "Violence"), ("suicide", "Self-harm"),
        ("overdose", "Self-harm"), ("terrorist", "Terrorism"),
        ("horrifying", "Fear-inducing"), ("terrifying", "Fear-inducing"),
        ("devastating", "Alarming"), ("death toll", "Disaster"),
        ("nude", "Adult content"), ("naked", "Adult content"),
        ("nsfw", "Adult content"), ("porn", "Adult content"),
        ("sex tape", "Adult content"), ("leaked photos", "Privacy violation"),
        ("explicit", "Adult content"), ("onlyfans", "Adult content"),
        ("dead body", "Violence/death"), ("bodies found", "Violence/death"),
    ]

    private static let mediumRiskKeywords: [(String, String)] = [
        ("breaking news", "Breaking news"), ("crisis", "Crisis"),
        ("disaster", "Disaster"), ("pandemic", "Health crisis"),
        ("outbreak", "Health crisis"), ("recession", "Financial stress"),
        ("inflation", "Financial stress"), ("layoffs", "Job insecurity"),
        ("scandal", "Scandal"), ("outrage", "Outrage bait"),
        ("shocking", "Alarming"), ("act now", "Urgency pressure"),
        ("war", "Conflict"), ("arrested", "Crime"),
        ("sexual", "Adult content"), ("strip", "Adult content"),
    ]

    private func classifyWithHeuristics(text: String) -> (Bool, String) {
        let lower = text.lowercased()

        var score = 0
        var reasons: [String] = []
        for (p, r) in Self.highRiskKeywords   { if lower.contains(p) { score += 2; reasons.append(r) } }
        for (p, r) in Self.mediumRiskKeywords { if lower.contains(p) { score += 1; reasons.append(r) } }

        if score >= (text.count > 100 ? 2 : 3) {
            return (false, reasons.prefix(2).joined(separator: " · "))
        }
        return (true, "Safe content")
    }

    // MARK: - AI Chat

    func chat(message: String) async -> String {
        return chatHeuristic(message: message)
    }

    private func chatHeuristic(message: String) -> String {
        let l = message.lowercased()
        if l.contains("how many")                          { return "Check the Analysis sub-tab in DevTools → AI for the live safe/unsafe count." }
        if l.contains("unsafe") && l.contains("what")     { return "Unsafe = likely to trigger anxiety: violence, disasters, financial doom, health scares, or urgency bait." }
        if l.contains("reading mode")                      { return "Tap the book icon in the bottom toolbar to toggle reading mode." }
        if l.contains("remove")                            { return "Enable 'Remove Unsafe Content' in Settings → Privacy → AI Content Filter." }
        if l.contains("how") && l.contains("work")        { return "Short text uses keyword matching. Longer text runs through Laya on MLX Swift directly on your device; no server or cloud API is used." }
        if l.contains("hello") || l.trimmingCharacters(in: .whitespaces) == "hi" { return "Hi! Ask me about the page analysis, why something was flagged, or any Drome feature." }
        return "I'm Drome's local AI helper. Ask me about content safety results, browser features, or why something was flagged."
    }

}
