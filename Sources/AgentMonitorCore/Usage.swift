import Foundation

/// Account-wide Claude subscription limits from a response or usage request.
public struct Usage: Equatable, Sendable {
    public let sessionPercent: Int
    public let sessionResetAt: Date
    public let weekPercent: Int?
    public let weekResetAt: Date?
    public let observedAt: Date

    public init(sessionPercent: Int, sessionResetAt: Date, weekPercent: Int? = nil,
                weekResetAt: Date? = nil, observedAt: Date = Date()) {
        self.sessionPercent = sessionPercent
        self.sessionResetAt = sessionResetAt
        self.weekPercent = weekPercent
        self.weekResetAt = weekResetAt
        self.observedAt = observedAt
    }

    /// A cached snapshot outlives its windows; a window whose reset has passed is
    /// empty until fresh usage arrives.
    public func sessionPercent(at now: Date) -> Int { sessionResetAt <= now ? 0 : sessionPercent }

    public func weekPercent(at now: Date) -> Int? {
        guard let weekPercent else { return nil }
        if let weekResetAt, weekResetAt <= now { return 0 }
        return weekPercent
    }

    /// The earliest reset still ahead, when the displayed usage next changes on its own.
    public func nextReset(after now: Date) -> Date? {
        [sessionResetAt, weekResetAt].compactMap { $0 }.filter { $0 > now }.min()
    }
}
