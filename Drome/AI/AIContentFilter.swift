import Foundation
import WebKit
import FoundationModels

// MARK: - Structured output for Apple Foundation Models

@available(iOS 26.0, *)
@Generable
struct ContentSafetyResult {
    @Guide(description: "true if content is safe for someone with anxiety, false if it could trigger anxiety")
    var safe: Bool

    @Guide(description: "3 to 6 word phrase explaining the classification")
    var reason: String
}

// MARK: - AIContentFilter

final class AIContentFilter {

    // Minimum chars to bother classifying at all
    private let minBlockLength = 25

    // Token safety: 400 chars ≈ 130 tokens. Fresh session overhead ≈ 65 tokens (instructions).
    // Total ≈ 225 tokens per session — well under the 4096-token context window.
    private let maxBlockChars = 400

    private let systemInstructions = """
    You are a mental health content safety classifier embedded in a web browser. \
    Decide whether a piece of web page text is safe for someone with anxiety. \
    UNSAFE: violence, death, crime, disasters, health crises, financial doom, \
    recession, layoffs, outrage bait, alarming statistics, high-urgency pressure language. \
    SAFE: informational, educational, entertainment, how-to, product descriptions, reviews, neutral reporting. \
    Be decisive.
    """

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

        let meaningful = raw.filter { (($0["text"] as? String)?.count ?? 0) >= minBlockLength }
        log(devToolsVM, "📄 \(raw.count) blocks, \(meaningful.count) qualify (≥\(minBlockLength) chars)")

        guard !meaningful.isEmpty else {
            log(devToolsVM, "No qualifying blocks — try a page with article text")
            return
        }

        let capped = Array(meaningful.prefix(40))

        devToolsVM?.aiIsAnalyzing = true
        devToolsVM?.aiTotalCount = capped.count
        devToolsVM?.aiAnalyzedCount = 0

        // ── Step 2: Check AI availability ───────────────────────────────────
        let useAI: Bool
        if #available(iOS 26.0, *) {
            let avail = SystemLanguageModel.default.availability
            useAI = (avail == .available)
            log(devToolsVM, useAI
                ? "🤖 Apple Foundation Models available — routing long blocks to AI"
                : "⚠️ Foundation Models unavailable (\(avail)) — keyword fallback for all blocks")
        } else {
            useAI = false
            log(devToolsVM, "📋 iOS < 26 — keyword heuristics only")
        }

        // ── Step 3: Phase 1 — mark ALL candidates as pending (blue) at once ─
        let xpaths = capped.compactMap { $0["xpath"] as? String }
        let pendingScript = JavaScriptInjector.markAllPendingJS(xpaths: xpaths)
        webView.evaluateJavaScript(pendingScript, completionHandler: nil)
        log(devToolsVM, "⏳ Marked \(xpaths.count) elements as pending")

        // Small yield so the blue borders paint before we block on AI calls
        await Task.yield()

        // ── Step 4: Phase 2 — classify each block, update label as we go ────
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

            // Always run keyword pre-filter first — hard overrides FM
            let (kwSafe, kwReason) = classifyWithHeuristics(text: cleanedText)
            if !kwSafe {
                (isSafe, reason) = (false, kwReason)
                method = "kw"
            } else if words <= 3 {
                (isSafe, reason) = (true, "Safe content")
                method = "kw"
            } else if useAI, #available(iOS 26.0, *) {
                (isSafe, reason) = await classifyWithFoundationModels(text: truncated, devToolsVM: devToolsVM)
                method = "ai"
            } else {
                (isSafe, reason) = (kwSafe, kwReason)
                method = "kw"
            }

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
        devToolsVM?.aiIsAnalyzing = false

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

    // MARK: - Foundation Models (fresh session per block = clean context, ~225 tokens total)

    @available(iOS 26.0, *)
    @MainActor
    private func classifyWithFoundationModels(text: String, devToolsVM: DeveloperToolsViewModel?) async -> (Bool, String) {
        log(devToolsVM, "[AI→] Sending \(text.count) chars, \(wordCount(text)) words: \"\(String(text.prefix(120)).replacingOccurrences(of: "\n", with: " "))\"")
        do {
            let session = LanguageModelSession(
                model: SystemLanguageModel(useCase: .contentTagging),
                instructions: systemInstructions
            )
            let result = try await session.respond(to: text, generating: ContentSafetyResult.self)
            // Sanitize reason: strip anything after punctuation artifacts or brackets
            var reason = result.content.reason
            if let cut = reason.firstIndex(of: "[") { reason = String(reason[..<cut]) }
            if let cut = reason.firstIndex(of: "]") { reason = String(reason[..<cut]) }
            if let cut = reason.firstIndex(of: "*") { reason = String(reason[..<cut]) }
            reason = reason.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ",:;}")))
            if reason.isEmpty || reason.count > 60 { reason = result.content.safe ? "Safe content" : "Sensitive content" }
            log(devToolsVM, "[AI←] safe=\(result.content.safe) reason=\"\(reason)\"")
            return (result.content.safe, reason)

        } catch let err as LanguageModelSession.GenerationError {
            let errStr = "\(err)"
            log(devToolsVM, "[AI✗] GenerationError: \(errStr.prefix(120))")
            switch err {
            case .rateLimited, .concurrentRequests:
                log(devToolsVM, "[AI✗] Rate limited — falling back to keywords")
                return classifyWithHeuristics(text: text)
            case .guardrailViolation:
                log(devToolsVM, "[AI✗] Guardrail triggered — marking unsafe")
                return (false, "Sensitive content")
            case .exceededContextWindowSize:
                log(devToolsVM, "[AI✗] Context too large — falling back to keywords")
                let shorter = String(text.prefix(200))
                return classifyWithHeuristics(text: shorter)
            default:
                // refusal = Apple's FM refused because content is sensitive → treat as unsafe
                if errStr.contains("refusal") || errStr.contains("sensitive") || errStr.contains("Refusal") {
                    log(devToolsVM, "[AI✗] Apple refused (sensitive content) — marking unsafe")
                    return (false, "Sensitive content")
                }
                log(devToolsVM, "[AI✗] Unknown error — falling back to keywords")
                return classifyWithHeuristics(text: text)
            }
        } catch {
            log(devToolsVM, "[AI✗] Error: \(error.localizedDescription) — falling back to keywords")
            return classifyWithHeuristics(text: text)
        }
    }

    // MARK: - Keyword heuristics (used for ≤3-word blocks and FM fallback)

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
        } else if #available(iOS 26.0, *), SystemLanguageModel.default.availability == .available {
            (isSafe, reason) = await classifyWithFoundationModels(text: truncated, devToolsVM: devToolsVM)
            method = "ai"
        } else {
            (isSafe, reason) = (kwSafe, kwReason)
            method = "kw"
        }

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
        if #available(iOS 26.0, *), SystemLanguageModel.default.availability == .available {
            return await chatWithFoundationModels(message: message)
        }
        return chatHeuristic(message: message)
    }

    @available(iOS 26.0, *)
    private func chatWithFoundationModels(message: String) async -> String {
        do {
            let session = LanguageModelSession(instructions: """
                You are a concise assistant built into Drome, an iOS browser. \
                Help the user understand AI content safety analysis and browser features. \
                Keep answers to 2-3 sentences.
                """)
            let response = try await session.respond(to: message)
            return response.content
        } catch {
            return chatHeuristic(message: message)
        }
    }

    private func chatHeuristic(message: String) -> String {
        let l = message.lowercased()
        if l.contains("how many")                          { return "Check the Analysis sub-tab in DevTools → AI for the live safe/unsafe count." }
        if l.contains("unsafe") && l.contains("what")     { return "Unsafe = likely to trigger anxiety: violence, disasters, financial doom, health scares, or urgency bait." }
        if l.contains("reading mode")                      { return "Tap the book icon in the bottom toolbar to toggle reading mode." }
        if l.contains("remove")                            { return "Enable 'Remove Unsafe Content' in Settings → Privacy → AI Content Filter." }
        if l.contains("how") && l.contains("work")        { return "Short text (≤3 words) uses keyword matching. Longer text goes to Apple's on-device AI. No data leaves the device." }
        if l.contains("hello") || l.trimmingCharacters(in: .whitespaces) == "hi" { return "Hi! Ask me about the page analysis, why something was flagged, or any Drome feature." }
        return "I'm Drome's on-device AI. Ask me about content safety results, browser features, or why something was flagged."
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
