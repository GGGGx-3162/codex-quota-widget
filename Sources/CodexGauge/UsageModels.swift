import Foundation

struct QuotaMetric: Equatable, Sendable {
    let limitID: String
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date?
    let capturedAt: Date

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }
}

struct UsageSnapshot: Equatable, Sendable {
    var fiveHour: QuotaMetric?
    var weekly: QuotaMetric?
    var readAt: Date

    static let empty = UsageSnapshot(
        fiveHour: nil,
        weekly: nil,
        readAt: .now
    )
}
