import XCTest
@testable import Drome

final class PageScanSessionTests: XCTestCase {
    private let tabID = UUID()

    func testCancelledSessionRejectsLateResultsAndDropsQueuedWork() {
        var session = PageScanSession(tabID: tabID, navigationGeneration: 3)
        let candidate = PageScanCandidate(
            id: "story-1",
            xpath: "//*[@data-drome-block-id='story-1']",
            text: "Original content",
            fingerprint: "first"
        )
        XCTAssertTrue(session.enqueue(candidate))

        let sessionID = session.id
        session.cancel()

        XCTAssertFalse(session.accepts(
            sessionID: sessionID,
            selectedTabID: tabID,
            navigationGeneration: 3
        ))
        XCTAssertTrue(session.dequeueBatch(limit: 10).isEmpty)
    }

    func testSessionAcceptsOnlyMatchingSelectedTabAndNavigation() {
        let session = PageScanSession(tabID: tabID, navigationGeneration: 7)

        XCTAssertTrue(session.accepts(
            sessionID: session.id,
            selectedTabID: tabID,
            navigationGeneration: 7
        ))
        XCTAssertFalse(session.accepts(
            sessionID: session.id,
            selectedTabID: UUID(),
            navigationGeneration: 7
        ))
        XCTAssertFalse(session.accepts(
            sessionID: session.id,
            selectedTabID: tabID,
            navigationGeneration: 8
        ))
    }

    func testQueueCoalescesByElementAndKeepsNewestContent() {
        var session = PageScanSession(tabID: tabID, navigationGeneration: 1)
        let first = PageScanCandidate(id: "card", xpath: "//card", text: "Old", fingerprint: "old")
        let latest = PageScanCandidate(id: "card", xpath: "//card", text: "New", fingerprint: "new")

        XCTAssertTrue(session.enqueue(first))
        XCTAssertTrue(session.enqueue(latest))

        XCTAssertEqual(session.dequeueBatch(limit: 10), [latest])
    }

    func testBoundedDrainPreservesRemainingCandidates() {
        var session = PageScanSession(tabID: tabID, navigationGeneration: 1)
        for index in 0..<12 {
            XCTAssertTrue(session.enqueue(PageScanCandidate(
                id: "item-\(index)",
                xpath: "//item[\(index)]",
                text: "Text \(index)",
                fingerprint: "fingerprint-\(index)"
            )))
        }

        XCTAssertEqual(session.dequeueBatch(limit: 10).count, 10)
        XCTAssertEqual(session.dequeueBatch(limit: 10).map(\.id), ["item-10", "item-11"])
    }

    func testProcessedFingerprintIsNotQueuedAgainUntilContentChanges() {
        var session = PageScanSession(tabID: tabID, navigationGeneration: 1)
        let original = PageScanCandidate(id: "story", xpath: "//story", text: "Same", fingerprint: "same")
        let changed = PageScanCandidate(id: "story", xpath: "//story", text: "Changed", fingerprint: "changed")

        XCTAssertTrue(session.enqueue(original))
        XCTAssertEqual(session.dequeueBatch(limit: 1), [original])
        session.markProcessed(original)

        XCTAssertFalse(session.enqueue(original))
        XCTAssertTrue(session.enqueue(changed))
        XCTAssertEqual(session.dequeueBatch(limit: 1), [changed])
    }
}
