import WebKit

actor ContentBlocker {
    static let shared = ContentBlocker()

    private var cachedRuleList: WKContentRuleList?

    func ruleList() async throws -> WKContentRuleList {
        if let cached = cachedRuleList { return cached }
        let rules = try await compileRules()
        cachedRuleList = rules
        return rules
    }

    func invalidateCache() {
        cachedRuleList = nil
    }
}

private func compileRules() async throws -> WKContentRuleList {
    return try await withCheckedThrowingContinuation { cont in
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "DromeAdBlock",
            encodedContentRuleList: contentBlockingRulesJSON
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
