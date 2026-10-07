import Foundation
import AgentMonitorCore

// All requests in these checks are intercepted; no Keychain reads or live API calls.
private final class UsageURLProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let respond = Self.respond else { throw URLError(.badServerResponse) }
            let (status, headers, data) = try respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

func checkOAuthUsage() async {
    let now = Date(timeIntervalSince1970: 1_791_116_400)
    let response = Data(#"""
    {
      "five_hour": {"utilization":3.0,"resets_at":"2026-10-04T13:09:59.646834+00:00","limit_dollars":null},
      "seven_day": {"utilization":22.0,"resets_at":"2026-10-04T18:59:59.646860+00:00"},
      "seven_day_opus":null,"extra_usage":{"is_enabled":false},
      "limits":[{"kind":"weekly_all","percent":22}],"spend":{"enabled":false},
      "future_field":{"anything":true}
    }
    """#.utf8)
    do {
        let snapshot = try ClaudeUsageSnapshot.decode(response)
        let usage = snapshot.usage(observedAt: now)
        check(usage.sessionPercent == 3 && usage.weekPercent == 22, "OAuth parses both windows from supplied response")
        check(usage.sessionResetAt.timeIntervalSince1970 > now.timeIntervalSince1970,
              "OAuth parses fractional ISO timestamps and offset")
        check(usage.observedAt == now, "OAuth observation time supplied by caller")

        let noWeek = try ClaudeUsageSnapshot.decode(Data(#"{"five_hour":{"utilization":1e300,"resets_at":"2026-10-04T13:09:59Z"},"seven_day":null}"#.utf8))
        check(noWeek.usage(observedAt: now).sessionPercent == 100 && noWeek.weekUtilization == nil,
              "OAuth handles absent weekly data and safely clamps extreme percentages")
        let notStarted = try ClaudeUsageSnapshot.decode(Data(#"{"five_hour":{"utilization":0.0,"resets_at":null},"seven_day":{"utilization":22.0,"resets_at":"2026-10-04T18:59:59.646860+00:00"}}"#.utf8))
        let notStartedUsage = notStarted.usage(observedAt: now)
        check(notStartedUsage.sessionPercent(at: now) == 0 && notStartedUsage.weekPercent(at: now) == 22
              && notStartedUsage.nextReset(after: now) == snapshot.weekResetAt,
              "OAuth treats a null reset as a window that has not started")
        check(!notStarted.hasIncreased(since: snapshot), "a window that has not started is not activity")
        for invalid in [
            #"{"five_hour":{"utilization":3,"resets_at":"invalid"}}"#,
            #"{"five_hour":null,"seven_day":null}"#,
            #"{"five_hour":{"utilization":"secret-server-body","resets_at":null}}"#,
        ] {
            do {
                _ = try ClaudeUsageSnapshot.decode(Data(invalid.utf8))
                check(false, "OAuth rejects missing or malformed windows")
            } catch {
                check(!String(describing: error).contains("secret-server-body"),
                      "OAuth rejects invalid response without exposing response body")
            }
        }

        var policy = UsagePollingPolicy()
        policy.beganRequest(at: now, power: .pluggedIn)
        policy.succeeded(snapshot, at: now, power: .pluggedIn)
        check(policy.interval(power: .pluggedIn) == 120, "polling bootstraps at two minutes")
        check(policy.earliestRequest(power: .pluggedIn, now: now) == now.addingTimeInterval(120),
              "opening menu cannot bypass minimum request spacing")
        for expected in [240.0, 480, 900, 900] {
            policy.succeeded(snapshot, at: now, power: .pluggedIn)
            check(policy.interval(power: .pluggedIn) == expected, "unchanged usage backs off to \(Int(expected)) seconds")
        }
        check(policy.interval(power: .battery) == 1800 && policy.interval(power: .lowPower) == 3600,
              "idle polling caps at 30 minutes on battery and one hour in Low Power Mode")
        let fraction = try ClaudeUsageSnapshot.decode(Data(#"{"five_hour":{"utilization":3.1,"resets_at":"2026-10-04T13:09:59.646834+00:00"},"seven_day":{"utilization":22,"resets_at":"2026-10-04T18:59:59.646860+00:00"}}"#.utf8))
        check(fraction.usage(observedAt: now).sessionPercent == usage.sessionPercent,
              "fractional activity fixture has unchanged displayed percent")
        policy.succeeded(fraction, at: now, power: .pluggedIn)
        check(policy.interval(power: .pluggedIn) == 120, "fractional increase restores active polling")
        check(policy.interval(power: .battery) == 300 && policy.interval(power: .lowPower) == 600,
              "active polling is slower on battery and in Low Power Mode")
        let reset = try ClaudeUsageSnapshot.decode(Data(#"{"five_hour":{"utilization":0,"resets_at":"2026-10-04T18:09:59Z"},"seven_day":{"utilization":22,"resets_at":"2026-10-04T18:59:59.646860+00:00"}}"#.utf8))
        check(!reset.hasIncreased(since: snapshot), "window reset alone is not activity")
        let weeklyIncrease = try ClaudeUsageSnapshot.decode(Data(#"{"five_hour":{"utilization":3,"resets_at":"2026-10-04T13:09:59.646834+00:00"},"seven_day":{"utilization":22.1,"resets_at":"2026-10-04T18:59:59.646860+00:00"}}"#.utf8))
        check(weeklyIncrease.hasIncreased(since: snapshot), "weekly increase also detects activity")

        var localActivity = policy
        localActivity.succeeded(fraction, at: now, power: .pluggedIn)
        check(localActivity.interval(power: .pluggedIn) == 240, "local activity fixture starts idle")
        localActivity.detectedLocalActivity(at: now.addingTimeInterval(30), power: .pluggedIn)
        check(localActivity.nextPollAt == now.addingTimeInterval(120),
              "session activity advances idle poll while respecting minimum spacing")
        localActivity.succeeded(fraction, at: now.addingTimeInterval(120), power: .pluggedIn)
        check(localActivity.interval(power: .pluggedIn) == 120,
              "recent local activity keeps fast polling even below reported percentage precision")
        localActivity.succeeded(fraction, at: now.addingTimeInterval(600), power: .pluggedIn)
        check(localActivity.interval(power: .pluggedIn) == 240, "polling slows once local activity stops")

        policy.failed(.http(429, retryAfter: 0), at: now, power: .pluggedIn)
        check(policy.retryNotBefore == now.addingTimeInterval(300), "Retry-After zero still applies five-minute rate-limit cooldown")
        policy.failed(.http(429, retryAfter: nil), at: now, power: .pluggedIn)
        check(policy.retryNotBefore == now.addingTimeInterval(600), "repeated rate limits back off exponentially")
        policy.failed(.http(429, retryAfter: 7200), at: now, power: .pluggedIn)
        let cooldown = now.addingTimeInterval(7200)
        check(policy.retryNotBefore == cooldown, "long server Retry-After overrides local backoff cap")
        policy.receivedLocalUsage(at: now, power: .pluggedIn)
        policy.detectedLocalActivity(at: now, power: .pluggedIn)
        policy.powerChanged(to: .battery, now: now)
        check(policy.scheduledRequest(power: .battery, now: now) == cooldown,
              "local activity and power changes preserve endpoint cooldown")
        let restored = try JSONDecoder().decode(UsagePollingPolicy.self, from: JSONEncoder().encode(policy))
        check(restored.earliestRequest(power: .pluggedIn, now: now) == cooldown,
              "persisted cooldown survives restart and manual refresh")
        check(restored.earliestManualRequest(now: now) == cooldown,
              "explicit refresh respects a persisted server cooldown")
        policy.succeeded(snapshot, at: cooldown, power: .pluggedIn)
        check(policy.retryNotBefore == nil, "successful request clears error backoff")

        var auth = UsagePollingPolicy()
        auth.failed(.expiredCredentials, at: now, power: .pluggedIn)
        check(auth.retryNotBefore == now.addingTimeInterval(900), "expired session waits for Claude to renew credentials")
        check(auth.earliestManualRequest(now: now) == now,
              "explicit refresh skips local auth backoff after session renewal")
        auth.beganRequest(at: now, power: .pluggedIn)
        check(auth.earliestManualRequest(now: now) == now.addingTimeInterval(UsagePollingPolicy.manualSpacing),
              "explicit refreshes keep a short minimum spacing")
        var transport = UsagePollingPolicy()
        for _ in 0..<10 { transport.failed(nil, at: now, power: .pluggedIn) }
        check(transport.retryNotBefore == now.addingTimeInterval(3600), "transport failures back off to one hour")
        var power = UsagePollingPolicy()
        power.beganRequest(at: now, power: .pluggedIn)
        power.powerChanged(to: .lowPower, now: now)
        check(power.scheduledRequest(power: .lowPower, now: now) == now.addingTimeInterval(600),
              "entering Low Power Mode postpones pending request")
        power.powerChanged(to: .pluggedIn, now: now)
        check(power.scheduledRequest(power: .pluggedIn, now: now) == now.addingTimeInterval(120),
              "connecting power shortens pending interval")

        let credentials = try ClaudeOAuthCredentials.decode(Data(#"{"claudeAiOauth":{"accessToken":"test-token","refreshToken":"never-read","expiresAt":1791122400000}}"#.utf8), now: now)
        check(credentials.accessToken == "test-token" && credentials.expiresAt != nil,
              "Claude session decoding accepts millisecond expiry")
        for invalid in [#"{}"#, #"{"claudeAiOauth":{"accessToken":""}}"#,
                        #"{"claudeAiOauth":{"accessToken":"test-token","expiresAt":1}}"#,
                        #"{"claudeAiOauth":{"accessToken":"bad\nheader"}}"#] {
            do {
                _ = try ClaudeOAuthCredentials.decode(Data(invalid.utf8), now: now)
                check(false, "invalid credentials rejected")
            } catch {
                check(error is ClaudeUsageError, "missing, expired or invalid credentials rejected safely")
            }
        }
        check(ClaudeUsageClient.retryDelay("60", now: now) == 60, "numeric Retry-After parsed")
        check(ClaudeUsageClient.retryDelay("Sun, 04 Oct 2026 13:20:00 GMT", now: now) == 3600,
              "HTTP-date Retry-After parsed")
        check(ClaudeUsageClient.retryDelay("garbage", now: now) == nil, "invalid Retry-After falls back to policy")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UsageURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); UsageURLProtocol.respond = nil }
        let client = ClaudeUsageClient(session: session)
        UsageURLProtocol.respond = { request in
            check(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage"
                  && request.httpMethod == "GET", "client makes read-only usage request to Anthropic")
            check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token"
                  && request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20",
                  "client sends OAuth headers")
            return (200, [:], response)
        }
        let fetched = try await client.fetch(credentials: credentials)
        check(fetched.usage(observedAt: now) == usage, "client parses intercepted usage response")
        for status in [401, 403, 429, 503, 302] {
            UsageURLProtocol.respond = { _ in (status, ["Retry-After": "900"], Data("sensitive-body".utf8)) }
            do {
                _ = try await client.fetch(credentials: credentials)
                check(false, "HTTP \(status) rejected")
            } catch let error as ClaudeUsageError {
                check(error.retryAfter == 900 && !error.description.contains("sensitive-body"),
                      "HTTP \(status) preserves retry delay without leaking body")
                check(error.needsAuthentication == (status == 401 || status == 403),
                      "HTTP \(status) authentication classified correctly")
            }
        }
        UsageURLProtocol.respond = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.fetch(credentials: credentials)
            check(false, "offline request rejected")
        } catch {
            check(error is URLError, "offline failure propagates for adaptive backoff")
        }
    } catch {
        check(false, "OAuth checks failed: \(error)")
    }
}
