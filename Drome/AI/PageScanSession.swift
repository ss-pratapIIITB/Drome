import Foundation

struct PageScanCandidate: Codable, Equatable {
    let id: String
    let xpath: String
    let text: String
    let fingerprint: String
}

struct PageScanSession {
    let id = UUID()
    let tabID: UUID
    let navigationGeneration: Int

    private(set) var isCancelled = false
    private var pendingOrder: [String] = []
    private var pendingByID: [String: PageScanCandidate] = [:]
    private var processedFingerprintByID: [String: String] = [:]

    init(tabID: UUID, navigationGeneration: Int) {
        self.tabID = tabID
        self.navigationGeneration = navigationGeneration
    }

    mutating func cancel() {
        isCancelled = true
        pendingOrder.removeAll(keepingCapacity: false)
        pendingByID.removeAll(keepingCapacity: false)
    }

    func accepts(
        sessionID: UUID,
        selectedTabID: UUID?,
        navigationGeneration: Int
    ) -> Bool {
        !isCancelled
            && id == sessionID
            && tabID == selectedTabID
            && self.navigationGeneration == navigationGeneration
    }

    @discardableResult
    mutating func enqueue(_ candidate: PageScanCandidate) -> Bool {
        guard !isCancelled,
              processedFingerprintByID[candidate.id] != candidate.fingerprint else {
            return false
        }

        if pendingByID[candidate.id] == nil {
            pendingOrder.append(candidate.id)
        }
        pendingByID[candidate.id] = candidate
        return true
    }

    mutating func dequeueBatch(limit: Int) -> [PageScanCandidate] {
        guard !isCancelled, limit > 0 else { return [] }

        let ids = Array(pendingOrder.prefix(limit))
        pendingOrder.removeFirst(ids.count)
        return ids.compactMap { pendingByID.removeValue(forKey: $0) }
    }

    mutating func markProcessed(_ candidate: PageScanCandidate) {
        guard !isCancelled else { return }
        processedFingerprintByID[candidate.id] = candidate.fingerprint
    }

    var hasPendingCandidates: Bool {
        !pendingOrder.isEmpty
    }
}
