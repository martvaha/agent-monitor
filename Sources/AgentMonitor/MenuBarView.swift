import SwiftUI
import AgentMonitorCore

/// The popover. The main pane lists each provider's limits as meters with a link
/// to its details, then menu-style commands; settings and details replace it in
/// place, each with a back chevron.
struct MenuBarView: View {
    enum Pane: Equatable {
        case main, settings, details(Provider)
    }

    @ObservedObject var store: UsageStore
    @ObservedObject var codexStore: CodexStore
    @State var pane: Pane = .main

    @AppStorage(MenuBarStyle.Key.claudeColor) private var claudeColor = BarColor.terracotta
    @AppStorage(MenuBarStyle.Key.codexColor) private var codexColor = BarColor.primary
    @AppStorage(MenuBarStyle.Key.warning) private var warning = LimitWarning.at90
    @AppStorage(MenuBarStyle.Key.fill) private var fill = BarFill.remaining
    @AppStorage(MenuBarStyle.Key.refreshOnOpen) private var refreshOnOpen = true

    var body: some View {
        // Measure one concrete container when switching between panes.
        VStack(spacing: 0) {
            switch pane {
            case .main:
                main
            case .settings:
                MenuBarSettingsView(claude: store.usage, codex: codexStore.usage) { pane = .main }
                    .padding(16)
            case .details(let provider):
                ProviderDetailsView(provider: provider, store: store, codexStore: codexStore,
                                    color: color(for: provider)) { pane = .main }
                    .padding(16)
            }
        }
        .frame(width: 300)
        .onAppear {
            if refreshOnOpen { store.refreshNow() } else { store.reload() }
            codexStore.refresh()
            LoginItem.shared.refresh()
        }
    }

    /// Without "Refresh when opened", opening the popover only shortens an idle
    /// interval; an explicit refresh requests now, deferring only to a server cooldown.
    private func refresh() {
        store.refreshNow()
        codexStore.refresh()
    }

    private func color(for provider: Provider) -> NSColor {
        (provider == .claude ? claudeColor : codexColor).nsColor
    }

    /// Bars take the provider's menu-bar colour, switching to the warning colour
    /// past the configured threshold, as in the menu-bar icon.
    private func tint(_ provider: Provider, percent: Int) -> Color {
        if let threshold = warning.threshold, percent >= threshold {
            return Color(nsColor: MenuBarIcon.warningColor)
        }
        return Color(nsColor: color(for: provider))
    }

    private var showsCodex: Bool { !(codexStore.usage?.windows.isEmpty ?? true) }

    // MARK: Main pane

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            Divider().padding(.horizontal, 16)
            claudeSection
                .padding(16)
            if let codex = codexStore.usage, showsCodex {
                Divider().padding(.horizontal, 16)
                providerSection(.codex, plan: codex.planLabel, windows: codex.limitWindows) {}
                    .padding(16)
            }
            Divider().padding(.horizontal, 16)
            commands
                .padding(6)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent usage")
                    .font(.system(size: 15, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(updatedText(now: context.date))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: refresh) {
                Group {
                    if store.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.isBusy)
            .help("Refresh now")
        }
    }

    private func updatedText(now: Date) -> String {
        let latest = [store.lastUpdated, codexStore.lastUpdated].compactMap { $0 }.max()
        guard let latest else { return "Waiting for first update" }
        return "Updated \(TimeText.relative(latest, now: now))"
    }

    @ViewBuilder
    private var claudeSection: some View {
        if let usage = store.usage {
            providerSection(.claude, plan: nil, windows: usage.limitWindows) {
                claudeStatus
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                providerTitle(.claude, plan: nil)
                Text(store.errorMessage == nil
                     ? "Waiting for usage. Uses your existing Claude Code login, including Zed sessions."
                     : "Couldn’t read usage.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                claudeStatus
            }
        }
    }

    /// Stale-data and permission notices for Claude, with their recovery action.
    @ViewBuilder
    private var claudeStatus: some View {
        if let error = store.errorMessage {
            Callout(message: store.usage == nil ? error : "Showing last-known usage. \(error)")
        }
        if store.needsKeychainAuthorization || store.isAuthorizingKeychain {
            Button(store.isAuthorizingKeychain ? "Waiting for permission…" : "Allow Keychain Access…") {
                store.authorizeKeychain()
            }
            .controlSize(.small)
            .disabled(store.isAuthorizingKeychain)
            .help("Enter your login Keychain password and choose Always Allow. macOS requires a password for this credential.")
        } else if store.errorMessage != nil {
            Button("Retry") { store.retry() }
                .controlSize(.small)
                .help("Respects Claude’s rate-limit cooldown. Background checks never show permission dialogs.")
        }
    }

    private func providerTitle(_ provider: Provider, plan: String?) -> some View {
        HStack(spacing: 8) {
            ProviderLogoView(provider: provider, color: color(for: provider), size: 20)
            Text(provider.name)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if let plan {
                Text(plan)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func providerSection<Status: View>(_ provider: Provider, plan: String?, windows: [LimitWindow],
                                               @ViewBuilder status: () -> Status) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            providerTitle(provider, plan: plan)
            ForEach(windows) { window in
                LimitMeter(window: window, tint: tint(provider, percent: window.percent), fill: fill)
            }
            status()
            NavigationRow(title: "Details") { pane = .details(provider) }
        }
    }

    private var commands: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Refresh Now", symbol: "arrow.clockwise", key: "r", action: refresh)
            MenuRow(title: "Settings…", symbol: "gearshape", key: ",") { pane = .settings }
            MenuRow(title: "Quit Agent Monitor", symbol: "power", key: "q") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
