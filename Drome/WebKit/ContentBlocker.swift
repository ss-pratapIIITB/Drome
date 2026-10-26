import WebKit

@MainActor
final class ContentBlocker {
    static let shared = ContentBlocker()

    private var cachedRuleList: WKContentRuleList?
    private var cachedCosmeticRuleList: WKContentRuleList?
    private var loadingTask: Task<WKContentRuleList, Error>?
    private var cosmeticLoadingTask: Task<WKContentRuleList, Error>?

    private init() {}

    func ruleList() async throws -> WKContentRuleList {
        if let cachedRuleList { return cachedRuleList }
        if let loadingTask { return try await loadingTask.value }

        let task = Task { try await self.loadRuleList() }
        loadingTask = task

        do {
            let ruleList = try await task.value
            cachedRuleList = ruleList
            loadingTask = nil
            return ruleList
        } catch {
            loadingTask = nil
            throw error
        }
    }

    /// Cosmetic layer: hides ad slots and sponsored modules that network
    /// blocking leaves behind as empty frames.
    func cosmeticRuleList() async throws -> WKContentRuleList {
        if let cachedCosmeticRuleList { return cachedCosmeticRuleList }
        if let cosmeticLoadingTask { return try await cosmeticLoadingTask.value }

        let task = Task {
            try await compile(
                identifier: "DromeAdBlockCosmetic",
                json: cosmeticRulesJSON
            )
        }
        cosmeticLoadingTask = task

        do {
            let ruleList = try await task.value
            cachedCosmeticRuleList = ruleList
            cosmeticLoadingTask = nil
            return ruleList
        } catch {
            cosmeticLoadingTask = nil
            throw error
        }
    }

    func invalidateCache() {
        cachedRuleList = nil
        cachedCosmeticRuleList = nil
        loadingTask?.cancel()
        cosmeticLoadingTask?.cancel()
        loadingTask = nil
        cosmeticLoadingTask = nil
    }

    private func loadRuleList() async throws -> WKContentRuleList {
        if let cached = try? await lookupRuleList() {
            return cached
        }
        return try await compile(identifier: "DromeAdBlock", json: contentBlockingRulesJSON)
    }

    private func lookupRuleList() async throws -> WKContentRuleList? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WKContentRuleList?, Error>) in
            WKContentRuleListStore.default().lookUpContentRuleList(
                forIdentifier: "DromeAdBlock"
            ) { ruleList, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ruleList)
                }
            }
        }
    }
}

@MainActor
private func compile(identifier: String, json: String) async throws -> WKContentRuleList {
    return try await withCheckedThrowingContinuation { cont in
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: json
        ) { ruleList, error in
            if let error {
                cont.resume(throwing: error)
            } else if let ruleList {
                cont.resume(returning: ruleList)
            } else {
                cont.resume(throwing: URLError(.unknown))
            }
        }
    }
}

// MARK: - EasyList-derived rules (common ad networks and trackers)
private let contentBlockingRulesJSON: String = """
[
  {"trigger":{"url-filter":"doubleclick\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"googlesyndication\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"googleadservices\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"pagead2\\\\.googlesyndication\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"amazon-adsystem\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"adsafeprotected\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"advertising\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"ads\\\\.yahoo\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"pixel\\\\.facebook\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"connect\\\\.facebook\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"ads\\\\.twitter\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"scorecardresearch\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"quantserve\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"outbrain\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"taboola\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"revcontent\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"adnxs\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"rubiconproject\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"openx\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"pubmatic\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"criteo\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"criteo\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"moatads\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"adsrvr\\\\.org","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"spotxchange\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"smartadserver\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"lijit\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"yieldmo\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"sharethrough\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"bidswitch\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"casalemedia\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"chartbeat\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"newrelic\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"mixpanel\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"segment\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"segment\\\\.io","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"hotjar\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"fullstory\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"mouseflow\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"inspectlet\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"crazyegg\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"bing\\\\.com\\/bat","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"analytics\\\\.twitter\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"mc\\\\.yandex\\\\.ru","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"googletagmanager\\\\.com","load-type":["third-party"]},"action":{"type":"ignore-previous-rules"}},
  {"trigger":{"url-filter":"www\\\\.google-analytics\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"ssl\\\\.google-analytics\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"stats\\\\.g\\\\.doubleclick\\\\.net"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"cdn\\\\.ampproject\\\\.org\\/[a-z]"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"pop-up|popunder|popup-ad","url-filter-is-case-sensitive":false},"action":{"type":"block"}},
  {"trigger":{"url-filter":"adserver","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"\\/ads\\/","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"\\/advert","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"banner-ad|bannerads","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"tpc\\\\.googlesyndication\\\\.com"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"securepubads\\\\.g\\\\.doubleclick\\\\.net"},"action":{"type":"block"}},
  {"trigger":{"url-filter":"media\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"imrworldwide\\\\.com","load-type":["third-party"]},"action":{"type":"block"}}
]
"""

// MARK: - Cosmetic ad rules (hide ad slots and sponsored modules)
// Only ad-specific containers and known ad frames; generic class matches are
// avoided so ordinary layout is not hidden.
private let cosmeticRulesJSON: String = """
[
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"ins.adsbygoogle"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".adsbygoogle"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"iframe[src*=\\"doubleclick.net\\"]"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"iframe[src*=\\"googlesyndication.com\\"]"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"[id^=\\"google_ads\\"]"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"[id^=\\"div-gpt-ad\\"]"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"[data-ad-slot]"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"[data-ad-unit]"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"[class*=\\"ad-slot\\"]"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"[class*=\\"ad-unit\\"]"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"[id^=\\"taboola\\"]"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"[class*=\\"taboola\\"]"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"[id^=\\"outbrain\\"]"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".OUTBRAIN"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".trc_related_container"}},
  {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"amp-ad"}},
  {"trigger":{"url-filter":"adform\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"teads\\\\.tv","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"3lift\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"33across\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"adition\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"yieldlab\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"adroll\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"ad-delivery\\\\.net","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"adnxs-simple\\\\.com","load-type":["third-party"]},"action":{"type":"block"}},
  {"trigger":{"url-filter":"appnexus\\\\.com","load-type":["third-party"]},"action":{"type":"block"}}
]
"""
