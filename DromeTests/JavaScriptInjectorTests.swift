import XCTest
@testable import Drome

final class JavaScriptInjectorTests: XCTestCase {
    func testMutationObserverTracksExpandedAndTextChangedContent() {
        let script = JavaScriptInjector.injectMutationObserverJS()

        XCTAssertTrue(script.contains("characterData: true"))
        XCTAssertTrue(script.contains("attributes: true"))
        XCTAssertTrue(script.contains("'aria-expanded'"))
        XCTAssertTrue(script.contains("'hidden'"))
        XCTAssertTrue(script.contains("fingerprint"))
        XCTAssertTrue(script.contains("data-drome-block-id"))
    }

    func testExtractionSkipsOnlyUnchangedClassifiedElements() {
        let script = JavaScriptInjector.extractContentBlocksJS()

        XCTAssertTrue(script.contains("data-drome-fingerprint"))
        XCTAssertTrue(script.contains("data-drome-safe"))
        XCTAssertTrue(script.contains("fingerprint"))
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
