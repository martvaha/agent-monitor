import Foundation
import Combine
import CoreServices
import AgentMonitorCore

/// Reads Codex usage from its rollout logs at launch, whenever the logs change, on a
/// slow fallback timer, and when the popover opens. A file fingerprint makes repeated
/// reads free when the logs have not changed.
@MainActor
final class CodexStore: ObservableObject {
    static let shared = CodexStore()

    @Published private(set) var usage: CodexUsage?
    @Published private(set) var lastUpdated: Date?

    private var fingerprint: String?
    private var isRefreshing = false
    private var started = false
    private var activityStream: FSEventStreamRef?
    private var fallbackTimer: DispatchSourceTimer?

    /// Local reads are cheap, so the fallback can be short; it also covers a sessions
    /// directory that did not exist yet when the watch was set up.
    private static let fallbackInterval: TimeInterval = 120

    func start() {
        guard !started else { return }
        started = true
        refresh()
        startWatchingSessions()
        startFallbackTimer()
    }

    /// Reads the newest snapshot off the main thread; keeps the previous value if the
    /// scan finds nothing (e.g. a build that logs `rate_limits: null`).
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let previousFingerprint = fingerprint
        Task.detached(priority: .utility) {
            let scan = CodexUsageReader.scan(changedFrom: previousFingerprint)
            await MainActor.run {
                self.isRefreshing = false
                guard let scan else { return }
                self.fingerprint = scan.fingerprint
                guard let scanned = scan.usage else { return }
                if let current = self.usage, scanned.observedAt <= current.observedAt { return }
                self.usage = scanned
                self.lastUpdated = scanned.observedAt
            }
        }
    }

    /// The OS recursively watches the sessions tree and batches writes, so an active
    /// Codex session is reflected within seconds without any polling.
    private func startWatchingSessions() {
        let sessions = CodexUsageReader.sessionsDirectory
        guard activityStream == nil,
              FileManager.default.fileExists(atPath: sessions.path) else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        guard let stream = FSEventStreamCreate(nil, { _, context, _, _, _, _ in
            guard let context else { return }
            let store = Unmanaged<CodexStore>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in store.refresh() }
        }, &context, [sessions.path] as CFArray,
           FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 5,
           FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)) else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        activityStream = stream
    }

    private func startFallbackTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.fallbackInterval,
                       repeating: Self.fallbackInterval, leeway: .seconds(15))
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.startWatchingSessions()
                self.refresh()
            }
        }
        timer.resume()
        fallbackTimer = timer
    }

    #if DEBUG
    func injectSample(_ usage: CodexUsage) {
        self.usage = usage
        self.lastUpdated = usage.observedAt
    }
    #endif
}
