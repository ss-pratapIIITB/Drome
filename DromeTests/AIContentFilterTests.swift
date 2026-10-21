import XCTest
@testable import Drome

final class AIContentFilterTests: XCTestCase {
    private let filter = AIContentFilter()

    func testBlocksShorterThanMinimumAreIgnored() async {
        let result = await filter.classify(text: "too short", useLaya: false)
        XCTAssertNil(result)
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

    func testHTMLIsStrippedBeforeLengthCheck() async {
        let result = await filter.classify(text: "<p>tiny</p>", useLaya: false)
        XCTAssertNil(result)
    }
}
