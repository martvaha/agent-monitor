import Foundation
import Combine
import Darwin
import AppKit
import IOKit.ps
import CoreServices
import AgentMonitorCore

/// Combines free status-line events with adaptive polling of the existing session.
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var usage: Usage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var needsKeychainAuthorization = false
    @Published private(set) var isAuthorizingKeychain = false
    @Published private(set) var isBusy = false

    private var directorySource: DispatchSourceFileSystemObject?
    private var activityStream: FSEventStreamRef?
    private var pollTimer: DispatchSourceTimer?
    private var fetchTask: Task<Void, Never>? {
        didSet { isBusy = fetchTask != nil }
    }
    private let client = ClaudeUsageClient()
    private var policy = UsagePollingPolicy()
    private var started = false
    private var isSleeping = false
    private var pendingCredentials: ClaudeOAuthCredentials?
    private var powerSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var powerMode: UsagePowerMode = .pluggedIn
    private let policyURL = UsageCache.fileURL.deletingLastPathComponent()
        .appendingPathComponent("polling.json")

    func start() {
        guard !started else { return }
        started = true
        if let data = try? Data(contentsOf: policyURL),
           let saved = try? JSONDecoder().decode(UsagePollingPolicy.self, from: data) {
            policy = saved
        }
        powerMode = currentPowerMode()
        reloadCache(signalActivity: false)
        startWatchingCache()
        startWatchingClaudeActivity()
        watchPowerAndSleep()
        // Discover missing permission immediately, even with a saved network
        // cooldown. This check cannot display UI or make an endpoint request.
        readKeychain(allowInteraction: false)
    }

    /// Opening the menu can shorten an idle interval, but respects the minimum
    /// request spacing and all server/error cooldowns.
    func reload() {
        reloadCache()
        schedulePoll(.earlier)
    }

    /// An explicit refresh requests now, bypassing idle intervals and local error
    /// backoff; only a server-imposed cooldown can defer it.
    func refreshNow() {
        reloadCache()
        schedulePoll(.manual)
    }

    func retry() {
        refreshNow()
    }

    /// Permission UI appears immediately and only after this explicit action.
    /// Reading the credential does not override the endpoint's saved cooldown.
    func authorizeKeychain() {
        readKeychain(allowInteraction: true)
    }

    private func readKeychain(allowInteraction: Bool) {
        guard fetchTask == nil, !isSleeping else { return }
        pollTimer?.cancel()
        pollTimer = nil
        isAuthorizingKeychain = allowInteraction
        fetchTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let credentials = try ClaudeOAuthCredentials.readFromKeychain(allowInteraction: allowInteraction)
                try Task.checkCancellation()
                await self?.keychainAuthorized(credentials, retainForNextRequest: allowInteraction)
            } catch {
                await self?.keychainReadFailed(error as? ClaudeUsageError,
                    cancelled: Task.isCancelled || error is CancellationError)
            }
        }
    }

    private func keychainAuthorized(_ credentials: ClaudeOAuthCredentials, retainForNextRequest: Bool) {
        fetchTask = nil
        isAuthorizingKeychain = false
        needsKeychainAuthorization = false
        if retainForNextRequest { pendingCredentials = credentials }
        errorMessage = nil
        schedulePoll(.earlier)
    }

    private func keychainReadFailed(_ error: ClaudeUsageError?, cancelled: Bool) {
        fetchTask = nil
        isAuthorizingKeychain = false
        if !cancelled {
            needsKeychainAuthorization = error == nil || error?.requiresKeychainAuthorization == true
            errorMessage = error?.description ?? "Claude’s Keychain session is unavailable."
        }
        // A local permission attempt must not change a server cooldown.
        schedulePoll()
    }

    private func reloadCache(signalActivity: Bool = true) {
        do {
            if let cached = try UsageCache.read(), acceptIfNewer(cached), signalActivity {
                // Ignore historical files when recovering from sleep/relaunch.
                if Date().timeIntervalSince(cached.observedAt) < powerMode.minimumInterval {
                    policy.receivedLocalUsage(at: Date(), power: powerMode)
                    savePolicy()
                    schedulePoll()
                }
            }
        } catch {
            if usage == nil { errorMessage = "\(error)" }
        }
    }

    @discardableResult
    private func acceptIfNewer(_ candidate: Usage) -> Bool {
        if let lastUpdated, candidate.observedAt <= lastUpdated { return false }
        usage = candidate
        lastUpdated = candidate.observedAt
        errorMessage = nil
        return true
    }

    private enum Urgency {
        case scheduled, earlier, manual
    }

    private func schedulePoll(_ urgency: Urgency = .scheduled) {
        guard started, !isSleeping, fetchTask == nil else { return }
        pollTimer?.cancel()
        let now = Date()
        let date = switch urgency {
        case .scheduled: policy.scheduledRequest(power: powerMode, now: now)
        case .earlier: policy.earliestRequest(power: powerMode, now: now)
        case .manual: policy.earliestManualRequest(now: now)
        }
        let delay = max(0, date.timeIntervalSince(now))
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // A single coalescible wake-up, rather than a repeating seconds timer.
        timer.schedule(deadline: .now() + delay, leeway: .seconds(Int(min(60, delay * 0.1))))
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.fetchUsage(manual: urgency == .manual) }
        }
        timer.resume()
        pollTimer = timer
    }

    private func fetchUsage(manual: Bool = false) {
        guard !isSleeping, fetchTask == nil else { return }
        pollTimer?.cancel()
        pollTimer = nil
        let now = Date()
        let earliest = manual ? policy.earliestManualRequest(now: now)
            : policy.earliestRequest(power: powerMode, now: now)
        guard now >= earliest else {
            schedulePoll(manual ? .manual : .scheduled)
            return
        }
        policy.beganRequest(at: now, power: powerMode)
        savePolicy()
        // A successful explicit approval supplies the next request, including
        // when the user chose Allow for just this read.
        let authorizedCredentials = pendingCredentials
        pendingCredentials = nil
        let client = client
        fetchTask = Task.detached(priority: .utility) { [weak self] in
            do {
                let credentials: ClaudeOAuthCredentials
                if let authorizedCredentials,
                   authorizedCredentials.expiresAt.map({ $0 > Date() }) ?? true {
                    credentials = authorizedCredentials
                } else {
                    credentials = try ClaudeOAuthCredentials.readFromKeychain(allowInteraction: false)
                }
                try Task.checkCancellation()
                let snapshot = try await client.fetch(credentials: credentials)
                try Task.checkCancellation()
                await self?.received(snapshot, observedAt: now)
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                // Do not expose transport descriptions or response bodies containing
                // sensitive authentication information in the UI or logs.
                await self?.fetchFailed(error as? ClaudeUsageError, cancelled: cancelled)
            }
        }
    }

    private func received(_ snapshot: ClaudeUsageSnapshot, observedAt: Date) {
        fetchTask = nil
        needsKeychainAuthorization = false
        policy.succeeded(snapshot, at: Date(), power: powerMode)
        // Reload first: a terminal event during this request may be newer.
        reloadCache(signalActivity: false)
        let candidate = snapshot.usage(observedAt: observedAt)
        if acceptIfNewer(candidate) {
            do { try UsageCache.write(candidate) }
            catch { errorMessage = "Usage updated, but the local cache could not be saved." }
        } else {
            errorMessage = nil
        }
        savePolicy()
        schedulePoll()
    }

    private func fetchFailed(_ error: ClaudeUsageError?, cancelled: Bool) {
        fetchTask = nil
        isAuthorizingKeychain = false
        if !cancelled {
            needsKeychainAuthorization = error?.requiresKeychainAuthorization == true
            policy.failed(error, at: Date(), power: powerMode)
            errorMessage = error?.description ?? "Could not reach Claude. Retrying later."
            savePolicy()
        }
        schedulePoll()
    }

    private func savePolicy() {
        // This file contains polling timestamps and usage, never session secrets.
        try? UsageCache.ensureDirectory(for: policyURL)
        if let data = try? JSONEncoder().encode(policy) {
            try? data.write(to: policyURL, options: .atomic)
        }
    }

    private func currentPowerMode() -> UsagePowerMode {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return .lowPower }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue(),
           source as String == kIOPSBatteryPowerValue {
            return .battery
        }
        return .pluggedIn
    }

    private func powerDidChange() {
        powerMode = currentPowerMode()
        policy.powerChanged(to: powerMode, now: Date())
        savePolicy()
        schedulePoll()
    }

    private func watchPowerAndSleep() {
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let store = Unmanaged<UsageStore>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in store.powerDidChange() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.powerDidChange() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isSleeping = true
                self?.pollTimer?.cancel()
                self?.pollTimer = nil
                self?.fetchTask?.cancel()
            }
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSleeping = false
                self.reloadCache()
                self.powerDidChange()
            }
        })
    }

    private func startWatchingClaudeActivity() {
        let root = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: projects.path) else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        // The OS recursively watches session directories and batches changes for
        // a minute. No directory scans, transcript reads, or per-token timers.
        guard let stream = FSEventStreamCreate(nil, { _, context, _, _, _, _ in
            guard let context else { return }
            let store = Unmanaged<UsageStore>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in store.localActivityDetected() }
        }, &context, [projects.path] as CFArray,
           FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 60,
           FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)) else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        activityStream = stream
    }

    private func localActivityDetected() {
        guard !isSleeping else { return }
        policy.detectedLocalActivity(at: Date(), power: powerMode)
        savePolicy()
        schedulePoll()
    }

    private func startWatchingCache() {
        guard directorySource == nil else { return }
        do {
            try UsageCache.ensureDirectory()
            let directory = UsageCache.fileURL.deletingLastPathComponent()
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else {
                errorMessage = "Could not watch the usage cache directory."
                return
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.reloadCache() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            directorySource = source
        } catch {
            errorMessage = "\(error)"
        }
    }

    #if DEBUG
    /// Inject a fixed value for snapshot rendering / previews.
    func injectSample(_ usage: Usage) {
        self.usage = usage
        self.lastUpdated = Date()
    }
    #endif
}
