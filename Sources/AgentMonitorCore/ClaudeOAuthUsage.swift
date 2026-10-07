import Foundation
import Security
import LocalAuthentication

/// Only the access token is read. Claude Code owns renewal of its shared session.
public struct ClaudeOAuthCredentials: Sendable {
    // The legacy Keychain interaction setting is process-wide. Serialize reads
    // so a background check cannot inherit an interactive check's setting.
    private static let keychainLock = NSLock()
    public let accessToken: String
    public let expiresAt: Date?

    public static func decode(_ data: Data, now: Date = Date()) throws -> Self {
        struct Envelope: Decodable {
            struct OAuth: Decodable {
                let accessToken: String?
                let expiresAt: Double?
            }
            let claudeAiOauth: OAuth?
        }
        guard let oauth = try? JSONDecoder().decode(Envelope.self, from: data),
              let token = oauth.claudeAiOauth?.accessToken, !token.isEmpty,
              !token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw ClaudeUsageError.noCredentials
        }
        // Claude Code stores expiresAt as milliseconds since the Unix epoch.
        let expiry = oauth.claudeAiOauth?.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        if let expiry, expiry <= now { throw ClaudeUsageError.expiredCredentials }
        return Self(accessToken: token, expiresAt: expiry)
    }

    /// Run off the main thread: Keychain access can block on its permission dialog.
    public static func readFromKeychain(allowInteraction: Bool, now: Date = Date()) throws -> Self {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        // Claude Code rewrites this item with /usr/bin/security on every token
        // renewal, which resets its partition list to Apple tools and drops any
        // Always Allow granted to this app. Reading through the same tool matches
        // the item's access list without a prompt. A locked Keychain would make
        // the tool ask for a password, so background reads skip it then.
        if allowInteraction || loginKeychainIsUnlocked(), let data = readWithSecurityTool() {
            return try decode(data, now: now)
        }
        // LAContext controls the Data Protection keychain, but Claude Code's
        // login Keychain item also needs the legacy interaction switch.
        let previousInteraction = try setLegacyInteractionAllowed(allowInteraction)
        defer { _ = try? setLegacyInteractionAllowed(previousInteraction) }
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { throw ClaudeUsageError.noCredentials }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
            throw ClaudeUsageError.keychainAuthorizationRequired
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw ClaudeUsageError.keychainUnavailable
        }
        return try decode(data, now: now)
    }

    /// Returns nil when the tool fails, so the caller falls back to SecItem and
    /// reports a precise error. The secret only travels through a private pipe.
    private static func readWithSecurityTool() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // Never let an unexpected dialog block the read indefinitely.
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
            if process.isRunning { process.terminate() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // The tool prints non-printable secrets as hex instead of raw bytes.
        if !text.hasPrefix("{"), let decoded = hexData(text) { return decoded }
        return Data(text.utf8)
    }

    private static func hexData(_ text: String) -> Data? {
        let digits = Array(text.utf8)
        guard !digits.isEmpty, digits.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: digits.count / 2)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let byte = UInt8(String(decoding: digits[index...index + 1], as: UTF8.self), radix: 16) else {
                return nil
            }
            data.append(byte)
        }
        return data
    }

    @diagnose(DeprecatedDeclaration, as: ignored)
    private static func loginKeychainIsUnlocked() -> Bool {
        var keychain: SecKeychain?
        var status: SecKeychainStatus = 0
        guard SecKeychainCopyDefault(&keychain) == errSecSuccess, let keychain,
              SecKeychainGetStatus(keychain, &status) == errSecSuccess else { return false }
        return status & SecKeychainStatus(kSecUnlockStateStatus) != 0
    }

    /// SecKeychain is deprecated, but nothing replaces its interaction switch
    /// for file-based Keychain items. Returns the previous setting.
    @diagnose(DeprecatedDeclaration, as: ignored)
    private static func setLegacyInteractionAllowed(_ allowed: Bool) throws -> Bool {
        var previous: DarwinBoolean = false
        guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(allowed) == errSecSuccess else {
            throw ClaudeUsageError.keychainUnavailable
        }
        return previous.boolValue
    }
}

public enum ClaudeUsageError: Error, CustomStringConvertible, Sendable {
    case noCredentials
    case expiredCredentials
    case keychainUnavailable
    case keychainAuthorizationRequired
    case http(Int, retryAfter: TimeInterval?)
    case invalidResponse
    case noSubscriptionUsage

    public var description: String {
        switch self {
        case .noCredentials: return "Sign in to Claude Code in Zed to enable usage updates."
        case .expiredCredentials: return "Claude’s session expired. Use Claude Code in Zed to renew it."
        case .keychainUnavailable: return "Claude’s Keychain session is unavailable. Unlock your Mac or allow access and retry."
        case .keychainAuthorizationRequired: return "Allow Keychain access, then choose Always Allow in the macOS prompt."
        case .http(401, _), .http(403, _): return "Claude’s session was rejected. Sign in again through Claude Code."
        case .http(429, _): return "Claude’s usage endpoint is rate limited. Updates will resume after a cooldown."
        case .http: return "Claude’s usage endpoint is unavailable. Retrying later."
        case .invalidResponse: return "Claude returned an unreadable usage response. Retrying later."
        case .noSubscriptionUsage: return "Claude’s session has no subscription usage limits."
        }
    }

    public var needsAuthentication: Bool {
        switch self {
        case .noCredentials, .expiredCredentials, .keychainUnavailable, .keychainAuthorizationRequired, .http(401, _), .http(403, _):
            return true
        default: return false
        }
    }

    public var requiresKeychainAuthorization: Bool {
        switch self {
        case .keychainAuthorizationRequired, .keychainUnavailable: return true
        default: return false
        }
    }

    public var retryAfter: TimeInterval? {
        if case .http(_, let delay) = self { return delay }
        return nil
    }

    public var isRateLimited: Bool {
        if case .http(429, _) = self { return true }
        return false
    }
}

/// Retains fractional utilization for activity detection, even when the UI rounds it.
/// A nil reset means the window has not started: Claude reports `resets_at: null`
/// until the first request after the previous window elapsed.
public struct ClaudeUsageSnapshot: Codable, Sendable {
    public let sessionUtilization: Double
    public let sessionResetAt: Date?
    public let weekUtilization: Double?
    public let weekResetAt: Date?

    public static func decode(_ data: Data) throws -> Self {
        struct Window: Decodable {
            let utilization: Double?
            let resets_at: String?
        }
        struct Envelope: Decodable {
            let five_hour: Window?
            let seven_day: Window?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ClaudeUsageError.invalidResponse
        }
        guard let window = envelope.five_hour, let percent = window.utilization else {
            throw ClaudeUsageError.noSubscriptionUsage
        }
        let reset = try parseReset(window.resets_at)
        guard percent.isFinite else { throw ClaudeUsageError.invalidResponse }
        let weekPercent = envelope.seven_day?.utilization
        let weekReset = try parseReset(envelope.seven_day?.resets_at)
        if let weekPercent, !weekPercent.isFinite { throw ClaudeUsageError.invalidResponse }
        return Self(sessionUtilization: percent, sessionResetAt: reset,
                    weekUtilization: weekPercent, weekResetAt: weekReset)
    }

    /// A window that has not started is shown like an elapsed one: empty, no countdown.
    public func usage(observedAt: Date) -> Usage {
        func percent(_ value: Double) -> Int { Int(min(max(value, 0), 100).rounded()) }
        return Usage(sessionPercent: percent(sessionUtilization), sessionResetAt: sessionResetAt ?? observedAt,
                     weekPercent: weekUtilization.map(percent),
                     weekResetAt: weekUtilization == nil ? nil : weekResetAt ?? observedAt,
                     observedAt: observedAt)
    }

    public func hasIncreased(since previous: Self) -> Bool {
        // A reset alone is not activity. A new window with nonzero usage is.
        let sessionIncreased = sessionResetAt == previous.sessionResetAt
            ? sessionUtilization > previous.sessionUtilization : sessionUtilization > 0
        let weekIncreased: Bool
        if let week = weekUtilization {
            weekIncreased = weekResetAt == previous.weekResetAt
                ? week > (previous.weekUtilization ?? 0) : week > 0
        } else {
            weekIncreased = false
        }
        return sessionIncreased || weekIncreased
    }

    /// Absent is valid (window not started); present but unparseable is not.
    private static func parseReset(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else { throw ClaudeUsageError.invalidResponse }
        return date
    }
}

/// Makes one read-only request for both the five-hour and weekly limits.
public struct ClaudeUsageClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = ClaudeUsageClient.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
    }

    public func fetch(credentials: ClaudeOAuthCredentials) async throws -> ClaudeUsageSnapshot {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClaudeUsageError.invalidResponse }
        guard response.statusCode == 200 else {
            throw ClaudeUsageError.http(response.statusCode,
                retryAfter: Self.retryDelay(response.value(forHTTPHeaderField: "Retry-After")))
        }
        return try ClaudeUsageSnapshot.decode(data)
    }

    public static func retryDelay(_ header: String?, now: Date = Date()) -> TimeInterval? {
        guard let header else { return nil }
        let value = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward the shared access token to a different endpoint.
        completionHandler(nil)
    }
}
