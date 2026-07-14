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

@available(iOS 26.0, *)
@Generable
struct BatchSafetyVerdict {
    @Guide(description: "1-based number of the ITEM this verdict is for")
    var item: Int

    @Guide(description: "true if the item is safe for someone with anxiety, false if it could trigger anxiety")
    var safe: Bool

    @Guide(description: "3 to 6 word phrase explaining the classification")
    var reason: String
}

@available(iOS 26.0, *)
@Generable
struct BatchContentSafetyResult {
    @Guide(description: "Exactly one verdict per numbered ITEM, in the same order as the input")
    var verdicts: [BatchSafetyVerdict]
}

// MARK: - AIContentFilter

final class AIContentFilter {

    // Minimum chars to bother classifying at all
    private let minBlockLength = 25

    // Per-item char cap. 400 chars ≈ 130 tokens, so a full batch of
    // `aiBatchSize` items ≈ 1300 tokens + ~100 instruction tokens + structured
    // output — comfortably inside the model's 4096-token context window.
    private let maxBlockChars = 400

    // Items per Foundation Models request. One request classifies the whole
    // batch, so a 40-block page costs 4 model calls instead of 40 — the model
    // processes the instructions once per batch instead of once per block.
    static let aiBatchSize = 10

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
        let useAI = foundationModelsAvailable()
        if #available(iOS 26.0, *) {
            log(devToolsVM, useAI
                ? "🤖 Apple Foundation Models available — batching long blocks to AI (\(Self.aiBatchSize)/request)"
                : "⚠️ Foundation Models unavailable (\(SystemLanguageModel.default.availability)) — keyword fallback for all blocks")
        } else {
            log(devToolsVM, "📋 iOS < 26 — keyword heuristics only")
        }

        // ── Step 3: Phase 1 — mark ALL candidates as pending (blue) at once ─
        let blocks: [(text: String, xpath: String)] = capped.compactMap { dict in
            guard let t = dict["text"] as? String, let x = dict["xpath"] as? String else { return nil }
            return (text: t, xpath: x)
        }
        let pendingScript = JavaScriptInjector.markAllPendingJS(xpaths: blocks.map { $0.xpath })
        webView.evaluateJavaScript(pendingScript, completionHandler: nil)
        log(devToolsVM, "⏳ Marked \(blocks.count) elements as pending")

        // Small yield so the blue borders paint before we block on AI calls
        await Task.yield()

        // ── Step 4: Phase 2 — classify (keywords first, then batched AI) ────
        let unsafeXPaths = await classifyAndLabel(
            blocks: blocks,
            webView: webView,
            devToolsVM: devToolsVM,
            useAI: useAI
        )

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

    // MARK: - Batched entry point for live DOM mutations

    @MainActor
    func classifyBlocks(
        _ incoming: [(text: String, xpath: String)],
        webView: WKWebView,
        devToolsVM: DeveloperToolsViewModel?,
        removeUnsafe: Bool
    ) async {
        let qualifying = incoming.filter { cleanText($0.text).count >= minBlockLength }
        guard !qualifying.isEmpty else { return }

        webView.evaluateJavaScript(
            JavaScriptInjector.markAllPendingJS(xpaths: qualifying.map { $0.xpath }),
            completionHandler: nil
        )

        devToolsVM?.aiTotalCount += qualifying.count
        let unsafeXPaths = await classifyAndLabel(
            blocks: qualifying,
            webView: webView,
            devToolsVM: devToolsVM,
            useAI: foundationModelsAvailable(),
            logPrefix: "[live]"
        )

        guard !Task.isCancelled, removeUnsafe, !unsafeXPaths.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }
        webView.evaluateJavaScript(JavaScriptInjector.applyFilterJS(xpaths: unsafeXPaths), completionHandler: nil)
    }

    // MARK: - Core classification pipeline (shared by page load + mutations)

    /// Keyword pre-filter resolves cheap cases immediately; everything else is
    /// classified by Foundation Models in batches of `aiBatchSize`. DOM labels
    /// are updated with one JS call per batch instead of one per block.
    /// Returns the xpaths of blocks judged unsafe.
    @MainActor
    private func classifyAndLabel(
        blocks: [(text: String, xpath: String)],
        webView: WKWebView,
        devToolsVM: DeveloperToolsViewModel?,
        useAI: Bool,
        logPrefix: String = ""
    ) async -> [String] {
        var unsafeXPaths: [String] = []
        var resolvedNow: [(xpath: String, isSafe: Bool, reason: String)] = []
        var aiQueue: [(text: String, xpath: String)] = []

        func record(xpath: String, text: String, isSafe: Bool, reason: String, method: String) {
            let preview = String(text.prefix(60))
            log(devToolsVM, "\(logPrefix)[\(method)] \(isSafe ? "✅" : "🔴") \"\(preview)\" — \(reason)")
            devToolsVM?.addAIResult(AIResult(xpath: xpath, isSafe: isSafe, reason: reason, preview: preview))
            if !isSafe { unsafeXPaths.append(xpath) }
        }

        // Pass 1 — keyword pre-filter (hard overrides FM); short blocks and
        // no-AI mode resolve here too
        for (rawText, xpath) in blocks {
            let cleaned = cleanText(rawText)
            guard cleaned.count >= minBlockLength else { continue }

            let (kwSafe, kwReason) = classifyWithHeuristics(text: cleaned)
            if !kwSafe {
                record(xpath: xpath, text: cleaned, isSafe: false, reason: kwReason, method: "kw")
                resolvedNow.append((xpath: xpath, isSafe: false, reason: kwReason))
            } else if wordCount(cleaned) <= 3 || !useAI {
                record(xpath: xpath, text: cleaned, isSafe: true, reason: kwReason, method: "kw")
                resolvedNow.append((xpath: xpath, isSafe: true, reason: kwReason))
            } else {
                aiQueue.append((text: String(cleaned.prefix(maxBlockChars)), xpath: xpath))
            }
        }

        if !resolvedNow.isEmpty {
            webView.evaluateJavaScript(JavaScriptInjector.updateLabelsBatchJS(resolvedNow), completionHandler: nil)
        }

        // Pass 2 — batched Foundation Models classification
        if useAI, #available(iOS 26.0, *) {
            var index = 0
            while index < aiQueue.count {
                guard !Task.isCancelled else {
                    log(devToolsVM, "🚫 Cancelled (navigated away)")
                    break
                }
                let chunk = Array(aiQueue[index..<min(index + Self.aiBatchSize, aiQueue.count)])
                index += chunk.count

                let verdicts = await classifyBatchWithFoundationModels(
                    texts: chunk.map { $0.text },
                    devToolsVM: devToolsVM
                )

                var updates: [(xpath: String, isSafe: Bool, reason: String)] = []
                for (i, item) in chunk.enumerated() {
                    let (isSafe, reason) = verdicts[i]
                    record(xpath: item.xpath, text: item.text, isSafe: isSafe, reason: reason, method: "ai")
                    updates.append((xpath: item.xpath, isSafe: isSafe, reason: reason))
                }
                webView.evaluateJavaScript(JavaScriptInjector.updateLabelsBatchJS(updates), completionHandler: nil)
                await Task.yield()
            }
        }

        return unsafeXPaths
    }

    private func foundationModelsAvailable() -> Bool {
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
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

    /// Strip generation artifacts (brackets, asterisks, trailing punctuation)
    private func sanitizeReason(_ raw: String, fallback: String) -> String {
        var reason = raw
        if let cut = reason.firstIndex(of: "[") { reason = String(reason[..<cut]) }
        if let cut = reason.firstIndex(of: "]") { reason = String(reason[..<cut]) }
        if let cut = reason.firstIndex(of: "*") { reason = String(reason[..<cut]) }
        reason = reason.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ",:;}")))
        if reason.isEmpty || reason.count > 60 { reason = fallback }
        return reason
    }

    // MARK: - Foundation Models: batched classification

    /// Classifies up to `aiBatchSize` texts in a single model request using
    /// numbered ITEMs and a structured array response. Fallback ladder:
    /// context overflow → split batch in half and retry; guardrail violation →
    /// reclassify items individually (so one sensitive item doesn't taint the
    /// batch); anything else → keyword heuristics.
    @available(iOS 26.0, *)
    @MainActor
    private func classifyBatchWithFoundationModels(
        texts: [String],
        devToolsVM: DeveloperToolsViewModel?
    ) async -> [(Bool, String)] {
        guard !texts.isEmpty else { return [] }
        if texts.count == 1 {
            return [await classifyWithFoundationModels(text: texts[0], devToolsVM: devToolsVM)]
        }

        let prompt = texts.enumerated()
            .map { "ITEM \($0.offset + 1): \($0.element)" }
            .joined(separator: "\n\n")
        log(devToolsVM, "[AI→] Batch of \(texts.count) items, \(prompt.count) chars")

        do {
            let session = LanguageModelSession(
                model: SystemLanguageModel(useCase: .contentTagging),
                instructions: systemInstructions + """
                 You will receive \(texts.count) numbered ITEMs. Classify each ITEM independently \
                and return exactly one verdict per ITEM with its item number.
                """
            )
            let result = try await session.respond(to: prompt, generating: BatchContentSafetyResult.self)

            var byItem: [Int: BatchSafetyVerdict] = [:]
            for v in result.content.verdicts { byItem[v.item] = v }

            return texts.enumerated().map { i, text in
                if let v = byItem[i + 1] {
                    let reason = sanitizeReason(v.reason, fallback: v.safe ? "Safe content" : "Sensitive content")
                    return (v.safe, reason)
                }
                log(devToolsVM, "[AI!] No verdict for item \(i + 1) — keyword fallback")
                return classifyWithHeuristics(text: text)
            }

        } catch let err as LanguageModelSession.GenerationError {
            let errStr = "\(err)"
            log(devToolsVM, "[AI✗] Batch GenerationError: \(errStr.prefix(120))")
            switch err {
            case .exceededContextWindowSize:
                log(devToolsVM, "[AI✗] Batch too large — splitting in half")
                let mid = texts.count / 2
                let left = await classifyBatchWithFoundationModels(texts: Array(texts[..<mid]), devToolsVM: devToolsVM)
                let right = await classifyBatchWithFoundationModels(texts: Array(texts[mid...]), devToolsVM: devToolsVM)
                return left + right
            case .guardrailViolation:
                log(devToolsVM, "[AI✗] Batch guardrail — reclassifying items individually")
                var out: [(Bool, String)] = []
                for t in texts {
                    if Task.isCancelled {
                        out.append(classifyWithHeuristics(text: t))
                    } else {
                        out.append(await classifyWithFoundationModels(text: t, devToolsVM: devToolsVM))
                    }
                }
                return out
            default:
                log(devToolsVM, "[AI✗] Falling back to keywords for batch")
                return texts.map { classifyWithHeuristics(text: $0) }
            }
        } catch {
            log(devToolsVM, "[AI✗] \(error.localizedDescription) — keyword fallback for batch")
            return texts.map { classifyWithHeuristics(text: $0) }
        }
    }

    // MARK: - Foundation Models: single-item classification

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
            let reason = sanitizeReason(
                result.content.reason,
                fallback: result.content.safe ? "Safe content" : "Sensitive content"
            )
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
        if l.contains("how") && l.contains("work")        { return "Short text (≤3 words) uses keyword matching. Longer text goes to Apple's on-device AI in batches of \(AIContentFilter.aiBatchSize). No data leaves the device." }
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
