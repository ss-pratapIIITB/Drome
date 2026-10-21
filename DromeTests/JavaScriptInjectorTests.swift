import XCTest
@testable import Drome

final class JavaScriptInjectorTests: XCTestCase {
    func testMutationObserverTracksExpandedAndTextChangedContent() {
        let script = JavaScriptInjector.injectMutationObserverJS()

        XCTAssertTrue(script.contains("characterData: true"))
        XCTAssertTrue(script.contains("attributes: true"))
        XCTAssertTrue(script.contains("'aria-expanded'"))
        XCTAssertTrue(script.contains("'hidden'"))
        XCTAssertTrue(script.contains("window.__dromeExtract.collect"))
        XCTAssertTrue(script.contains("attributeFilter"))
    }

    func testExtractionSkipsOnlyUnchangedClassifiedElements() {
        let script = JavaScriptInjector.extractContentBlocksJS()

        XCTAssertTrue(script.contains("window.__dromeExtract.collect"))
        XCTAssertTrue(script.contains("JSON.stringify"))
    }

    func testBatchLabelUpdateUsesOneScript() {
        let script = JavaScriptInjector.updateLabelsJS([
            .init(xpath: "//*[@data-drome-block-id='block-1']",
                  fingerprint: "abc-12",
                  isSafe: false,
                  reason: "Violence",
                  hideUnsafe: true)
        ])

        XCTAssertTrue(script.contains("data-drome-fingerprint"))
        XCTAssertTrue(script.contains("data-drome-safe"))
        XCTAssertTrue(script.contains("__drome_unsafe_hidden"))
        XCTAssertTrue(script.contains("block-1"))
    }

    func testUnsafeVisibilityUsesReversibleDromeClass() {
        let hide = JavaScriptInjector.setUnsafeHiddenJS(true)
        let reveal = JavaScriptInjector.setUnsafeHiddenJS(false)

        XCTAssertTrue(hide.contains("__drome_unsafe_hidden"))
        XCTAssertTrue(hide.contains("classList.add"))
        XCTAssertTrue(reveal.contains("classList.remove"))
        XCTAssertFalse(hide.contains("el.style.display"))
    }
}
