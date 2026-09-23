import Foundation
import WebKit

// MARK: - AIContentFilter

final class AIContentFilter {

    private let layaRuntime = LayaMLXRuntime.shared

    // Minimum chars to bother classifying at all
    private let minBlockLength = 25

    // Keep inference small and responsive; the native runtime also enforces its own input cap.
    private let maxBlockChars = 400

    // MARK: - Main entry (MainActor — WKWebView requires main thread)

    @MainActor
    func analyzeAndLabel(
        webView: WKWebView,
        devToolsVM: DeveloperToolsViewModel?,
        removeUnsafe: Bool
    ) async {
        guard !Task.isCancelled else { return }

        webView.evaluateJavaScript(JavaScriptInjector.clearAILabelsJS(), completionHandler: nil)
        log(devToolsVM, "🔍 Extracting content blocks…")

        // ── Step 1: Extract blocks ──────────────────────────────────────────
        guard let json = await evalJS(webView, JavaScriptInjector.extractContentBlocksJS()),
              let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            log(devToolsVM, "⚠️ Content extraction returned nothing — page may not have loaded")
            return
        }

        let meaningful = deduplicatedBlocks(raw)
        log(devToolsVM, "📄 \(raw.count) blocks, \(meaningful.count) unique blocks qualify (≥\(minBlockLength) chars)")

        guard !meaningful.isEmpty else {
            log(devToolsVM, "No qualifying blocks — try a page with article text")
            return
        }

        let capped = Array(meaningful.prefix(40))

        devToolsVM?.aiIsAnalyzing = true
        devToolsVM?.aiTotalCount = capped.count
        devToolsVM?.aiAnalyzedCount = 0
        defer { devToolsVM?.aiIsAnalyzing = false }

        // ── Step 2: Acknowledge every candidate immediately ────────────────
        // Do this before a first-use download or cold model load so the filter
        // never appears unresponsive.
        let xpaths = capped.compactMap { $0["xpath"] as? String }
        let pendingScript = JavaScriptInjector.markAllPendingJS(xpaths: xpaths)
        webView.evaluateJavaScript(pendingScript, completionHandler: nil)
        log(devToolsVM, "⏳ Marked \(xpaths.count) elements as pending")
        await Task.yield()

        // ── Step 3: Load Laya MLX on the device ─────────────────────────────
        log(devToolsVM, "🤖 Preparing on-device Laya MLX (first use downloads the model)…")
        let useAI: Bool
        do {
            try await layaRuntime.prepare()
            useAI = true
        } catch {
            useAI = false
            log(devToolsVM, "⚠️ Laya MLX failed to load: \(error.localizedDescription)")
        }
        log(devToolsVM, useAI
            ? "🤖 Laya MLX ready on device — routing long blocks to typed decisions"
            : "⚠️ Laya MLX unavailable — keyword fallback for all blocks")

        // ── Step 4: Classify each block, update label as we go ──────────────
        var unsafeXPaths: [String] = []

        for block in capped {
            guard !Task.isCancelled else {
                log(devToolsVM, "🚫 Cancelled (navigated away)")
                break
            }

            guard let rawText = block["text"] as? String,
                  let xpath = block["xpath"] as? String else { continue }

            let cleanedText = cleanText(rawText)
            guard cleanedText.count >= minBlockLength else { continue }

            let words = wordCount(cleanedText)
            let truncated = String(cleanedText.prefix(maxBlockChars))

            let (isSafe, reason): (Bool, String)
            let method: String

            // Always run keyword pre-filter first as a hard safety override.
            let (kwSafe, kwReason) = classifyWithHeuristics(text: cleanedText)
            if !kwSafe {
                (isSafe, reason) = (false, kwReason)
                method = "kw"
            } else if words <= 3 {
                (isSafe, reason) = (true, "Safe content")
                method = "kw"
            } else if useAI {
                (isSafe, reason) = await classifyWithLayaMLX(text: truncated, devToolsVM: devToolsVM)
                method = "laya"
            } else {
                (isSafe, reason) = (kwSafe, kwReason)
                method = "kw"
            }

            guard !Task.isCancelled else { break }

            let preview = String(cleanedText.prefix(60))
            log(devToolsVM, "[\(method)] \(isSafe ? "✅" : "🔴") \"\(preview)\" — \(reason)")

            // Update element from ⏳ → ✓/⚠
            let updateScript = JavaScriptInjector.updateLabelJS(xpath: xpath, isSafe: isSafe, reason: reason)
            webView.evaluateJavaScript(updateScript, completionHandler: nil)

            devToolsVM?.addAIResult(AIResult(xpath: xpath, isSafe: isSafe, reason: reason, preview: preview))
            if !isSafe { unsafeXPaths.append(xpath) }

            await Task.yield()
        }

        let safe = devToolsVM?.aiResults.filter { $0.isSafe }.count ?? 0
        let unsafe = devToolsVM?.aiResults.filter { !$0.isSafe }.count ?? 0
        log(devToolsVM, "✅ Complete — \(safe) safe · \(unsafe) unsafe · \(capped.count) total")

        // ── Step 5: Remove unsafe if setting is on ──────────────────────────
        guard !Task.isCancelled, removeUnsafe, !unsafeXPaths.isEmpty else { return }
        log(devToolsVM, "🗑 Removing \(unsafeXPaths.count) unsafe blocks in 1.2s…")
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard !Task.isCancelled else { return }
        webView.evaluateJavaScript(JavaScriptInjector.applyFilterJS(xpaths: unsafeXPaths), completionHandler: nil)
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

    private func deduplicatedBlocks(_ blocks: [[String: Any]]) -> [[String: Any]] {
        var order: [String] = []
        var longestByPath: [String: [String: Any]] = [:]

        for block in blocks {
            guard let text = block["text"] as? String,
                  text.count >= minBlockLength,
                  let path = block["xpath"] as? String,
                  !path.isEmpty else { continue }

            if longestByPath[path] == nil {
                order.append(path)
                longestByPath[path] = block
            } else if text.count > ((longestByPath[path]?["text"] as? String)?.count ?? 0) {
                longestByPath[path] = block
            }
        }

        return order.compactMap { longestByPath[$0] }
    }

    // MARK: - Laya MLX

    @MainActor
    private func classifyWithLayaMLX(text: String, devToolsVM: DeveloperToolsViewModel?) async -> (Bool, String) {
        log(devToolsVM, "[Laya→] Sending \(text.count) chars, \(wordCount(text)) words: \"\(String(text.prefix(120)).replacingOccurrences(of: "\n", with: " "))\"")
        do {
            let result = try await layaRuntime.classify(text)
            let latency = String(format: "%.1fms", result.latencyMs)
            log(devToolsVM, "[Laya←] safe=\(result.safe) confidence=\(String(format: "%.2f", result.confidence)) latency=\(latency) reason=\"\(result.reason)\"")
            return (result.safe, result.reason)
        } catch {
            log(devToolsVM, "[Laya✗] \(error.localizedDescription) — falling back to keywords")
            return classifyWithHeuristics(text: text)
        }
    }

    // MARK: - Keyword heuristics (short blocks and Laya fallback)

    private func classifyWithHeuristics(text: String) -> (Bool, String) {
        let lower = text.lowercased()

        let highRisk: [(String, String)] = [
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
        let mediumRisk: [(String, String)] = [
            ("breaking news", "Breaking news"), ("crisis", "Crisis"),
            ("disaster", "Disaster"), ("pandemic", "Health crisis"),
            ("outbreak", "Health crisis"), ("recession", "Financial stress"),
            ("inflation", "Financial stress"), ("layoffs", "Job insecurity"),
            ("scandal", "Scandal"), ("outrage", "Outrage bait"),
            ("shocking", "Alarming"), ("act now", "Urgency pressure"),
            ("war", "Conflict"), ("arrested", "Crime"),
            ("sexual", "Adult content"), ("strip", "Adult content"),
        ]

        var score = 0
        var reasons: [String] = []
        for (p, r) in highRisk   { if lower.contains(p) { score += 2; reasons.append(r) } }
        for (p, r) in mediumRisk { if lower.contains(p) { score += 1; reasons.append(r) } }

        if score >= (text.count > 100 ? 2 : 3) {
            return (false, reasons.prefix(2).joined(separator: " · "))
        }
        return (true, "Safe content")
    }

    // MARK: - Single block classifier (for live DOM mutations)

    @MainActor
    func classifySingleBlock(
        text: String,
        xpath: String,
        webView: WKWebView,
        devToolsVM: DeveloperToolsViewModel?,
        removeUnsafe: Bool
    ) async {
        let cleaned = cleanText(text)
        guard cleaned.count >= minBlockLength else { return }

        let truncated = String(cleaned.prefix(maxBlockChars))
        let words = wordCount(cleaned)

        let (isSafe, reason): (Bool, String)
        let method: String

        // Mark pending first
        webView.evaluateJavaScript(
            JavaScriptInjector.markAllPendingJS(xpaths: [xpath]),
            completionHandler: nil
        )

        let (kwSafe, kwReason) = classifyWithHeuristics(text: cleaned)
        if !kwSafe {
            (isSafe, reason) = (false, kwReason)
            method = "kw"
        } else if words <= 3 {
            (isSafe, reason) = (true, "Safe content")
            method = "kw"
        } else if (try? await layaRuntime.prepare()) != nil {
            (isSafe, reason) = await classifyWithLayaMLX(text: truncated, devToolsVM: devToolsVM)
            method = "laya"
        } else {
            (isSafe, reason) = (kwSafe, kwReason)
            method = "kw"
        }

        guard !Task.isCancelled else { return }

        let preview = String(cleaned.prefix(60))
        log(devToolsVM, "[live/\(method)] \(isSafe ? "✅" : "🔴") \"\(preview)\" — \(reason)")

        webView.evaluateJavaScript(
            JavaScriptInjector.updateLabelJS(xpath: xpath, isSafe: isSafe, reason: reason),
            completionHandler: nil
        )
        devToolsVM?.addAIResult(AIResult(xpath: xpath, isSafe: isSafe, reason: reason, preview: preview))

        if !isSafe && removeUnsafe {
            try? await Task.sleep(nanoseconds: 600_000_000)
            webView.evaluateJavaScript(
                JavaScriptInjector.applyFilterJS(xpaths: [xpath]),
                completionHandler: nil
            )
        }
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

    // MARK: - Helpers

    @MainActor
    private func evalJS(_ webView: WKWebView, _ script: String) async -> String? {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(script) { result, error in
                if let error = error { print("[Drome AI] JS error: \(error.localizedDescription)") }
                cont.resume(returning: result as? String)
            }
        }
    }

    @MainActor
    private func log(_ vm: DeveloperToolsViewModel?, _ msg: String) {
        print("[Drome AI] \(msg)")
        vm?.addConsoleEntry(ConsoleEntry(
            level: .info, message: msg, source: "Drome AI",
            line: nil, column: nil, timestamp: .now, tabID: UUID()
        ))
    }
}
