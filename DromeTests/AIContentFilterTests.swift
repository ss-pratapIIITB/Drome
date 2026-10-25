import XCTest
@testable import Drome

final class AIContentFilterTests: XCTestCase {
    private let filter = AIContentFilter()

    func testShortTextIsKeywordClassifiedInsteadOfDropped() async {
        // Short strings must not bypass the keyword guard: explicit image alt
        // text is often only two or three words.
        let result = await filter.classify(text: "too short", useLaya: false)
        XCTAssertEqual(result?.isSafe, true)
        XCTAssertEqual(result?.method, "kw")
    }

    func testShortExplicitAltTextIsFlagged() async {
        let nude = await filter.classify(text: "nude models", useLaya: true)
        let porn = await filter.classify(text: "porn", useLaya: true)

        XCTAssertEqual(nude?.isSafe, false)
        XCTAssertEqual(nude?.method, "kw")
        XCTAssertEqual(nude?.reason, "Adult content")
        XCTAssertEqual(porn?.isSafe, false)
        XCTAssertEqual(porn?.reason, "Adult content")
    }

    func testBenignShortTextStaysSafe() async {
        let result = await filter.classify(text: "Sunset over the bay", useLaya: true)

        XCTAssertEqual(result?.isSafe, true)
        XCTAssertEqual(result?.method, "kw")
    }

    func testAmbiguousTermsStayScoreBased() async {
        // "explicit" in a music context must not flag on its own.
        let result = await filter.classify(text: "Album review with explicit lyrics", useLaya: false)
        XCTAssertEqual(result?.isSafe, true)
    }

    func testHighRiskKeywordIsFlaggedWithoutLoadingTheModel() async {
        let result = await filter.classify(
            text: "Police reported a murder and a shooting in the neighborhood today.",
            useLaya: false
        )

        XCTAssertEqual(result?.isSafe, false)
        XCTAssertEqual(result?.method, "kw")
        XCTAssertNil(result?.confidence)
    }

    func testOrdinaryTextUsesKeywordPathWhenLayaIsDisabled() async {
        let result = await filter.classify(
            text: "This article explains how to bake sourdough bread at home.",
            useLaya: false
        )

        XCTAssertEqual(result?.isSafe, true)
        XCTAssertEqual(result?.method, "kw")
    }

    func testShortTextStaysOnKeywordPathEvenWhenLayaIsEnabled() async {
        let result = await filter.classify(text: "Drome browsering extraordinaire", useLaya: true)

        XCTAssertEqual(result?.isSafe, true)
        XCTAssertEqual(result?.method, "kw")
    }

    func testMediumRiskThresholdScalesWithTextLength() async {
        let short = "A crisis and a disaster happened today."
        let long = short + String(
            repeating: "This is additional context about the situation. ",
            count: 3
        )

        let shortResult = await filter.classify(text: short, useLaya: false)
        let longResult = await filter.classify(text: long, useLaya: false)

        XCTAssertEqual(shortResult?.isSafe, true)
        XCTAssertEqual(longResult?.isSafe, false)
    }

    func testHTMLIsStrippedBeforeClassification() async {
        let result = await filter.classify(text: "<p>nude models</p>", useLaya: false)

        XCTAssertEqual(result?.isSafe, false)
        XCTAssertEqual(result?.reason, "Adult content")
    }

    func testBatchClassificationPreservesOrder() async {
        let results = await filter.classifyBatch(
            texts: [
                "nude models",
                "Police reported a murder and a shooting in the neighborhood today.",
                "This article explains how to bake sourdough bread at home.",
            ],
            useLaya: false
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0]?.isSafe, false)
        XCTAssertEqual(results[1]?.isSafe, false)
        XCTAssertEqual(results[2]?.isSafe, true)
    }
}
