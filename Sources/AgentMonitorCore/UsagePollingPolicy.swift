import Foundation

public enum UsagePowerMode: Sendable {
    case pluggedIn, battery, lowPower

    public var minimumInterval: TimeInterval {
        switch self {
        case .pluggedIn: return 120
        case .battery: return 300
        case .lowPower: return 600
        }
    }

    fileprivate var maximumInterval: TimeInterval {
        switch self {
        case .pluggedIn: return 900
        case .battery: return 1800
        case .lowPower: return 3600
        }
    }
}

/// Persisted without credentials so restarting or opening the menu cannot defeat
/// an endpoint cooldown. Successful idle polls back off independently of failures.
public struct UsagePollingPolicy: Codable, Sendable {
    public private(set) var lastAttemptAt: Date?
    public private(set) var nextPollAt: Date?
    public private(set) var retryNotBefore: Date?
    /// The part of `retryNotBefore` the server asked for (429 or Retry-After),
    /// which even an explicit refresh must respect.
    public private(set) var serverRetryNotBefore: Date?
    private var previousSnapshot: ClaudeUsageSnapshot?
    private var lastLocalActivityAt: Date?
    private var idlePolls = 0
    private var failures = 0

    /// Minimum spacing between explicit refreshes, so repeated clicks stay cheap.
    public static let manualSpacing: TimeInterval = 15

    public init() {}

    public func interval(power: UsagePowerMode) -> TimeInterval {
        min(power.maximumInterval, power.minimumInterval * pow(2, Double(min(idlePolls, 4))))
    }

    public func earliestRequest(power: UsagePowerMode, now: Date) -> Date {
        let minimum = lastAttemptAt?.addingTimeInterval(power.minimumInterval) ?? now
        return max(minimum, retryNotBefore ?? now)
    }

    /// An explicit refresh skips idle intervals and local error backoff (the user
    /// may just have renewed Claude's session), but not a server cooldown.
    public func earliestManualRequest(now: Date) -> Date {
        let minimum = lastAttemptAt?.addingTimeInterval(Self.manualSpacing) ?? now
        return max(minimum, serverRetryNotBefore ?? now)
    }

    public func scheduledRequest(power: UsagePowerMode, now: Date) -> Date {
        max(nextPollAt ?? now, earliestRequest(power: power, now: now))
    }

    public mutating func beganRequest(at now: Date, power: UsagePowerMode) {
        lastAttemptAt = now
        nextPollAt = now.addingTimeInterval(power.minimumInterval)
    }

    public mutating func succeeded(_ snapshot: ClaudeUsageSnapshot, at now: Date, power: UsagePowerMode) {
        if let lastLocalActivityAt,
           now.timeIntervalSince(lastLocalActivityAt) <= power.minimumInterval + 60 {
            idlePolls = 0
        } else if let previousSnapshot {
            idlePolls = snapshot.hasIncreased(since: previousSnapshot) ? 0 : min(idlePolls + 1, 4)
        } else {
            // Bootstrap with a short follow-up to determine whether usage is active.
            idlePolls = 0
        }
        previousSnapshot = snapshot
        failures = 0
        retryNotBefore = nil
        serverRetryNotBefore = nil
        nextPollAt = now.addingTimeInterval(interval(power: power))
    }

    public mutating func failed(_ error: ClaudeUsageError?, at now: Date, power: UsagePowerMode) {
        failures = min(failures + 1, 6)
        let base: TimeInterval = error?.needsAuthentication == true ? 900
            : error?.isRateLimited == true ? 300 : power.minimumInterval
        let delay = max(power.minimumInterval, min(3600, base * pow(2, Double(failures - 1))),
                        error?.retryAfter ?? 0)
        retryNotBefore = now.addingTimeInterval(delay)
        serverRetryNotBefore = error?.isRateLimited == true ? retryNotBefore
            : error?.retryAfter.map { now.addingTimeInterval($0) }
        nextPollAt = retryNotBefore
    }

    /// A fresh terminal response is an activity signal and supplies usage for free.
    /// It delays the next network request, but never shortens an error cooldown.
    public mutating func receivedLocalUsage(at now: Date, power: UsagePowerMode) {
        idlePolls = 0
        nextPollAt = max(now.addingTimeInterval(power.minimumInterval), retryNotBefore ?? now)
    }

    /// Session log writes are an activity hint, without requiring log contents.
    /// Unlike a status-line update they supply no usage, so bring the poll forward.
    public mutating func detectedLocalActivity(at now: Date, power: UsagePowerMode) {
        lastLocalActivityAt = now
        idlePolls = 0
        nextPollAt = earliestRequest(power: power, now: now)
    }

    public mutating func powerChanged(to power: UsagePowerMode, now: Date) {
        let next = lastAttemptAt?.addingTimeInterval(interval(power: power)) ?? now
        nextPollAt = max(next, earliestRequest(power: power, now: now))
    }
}
