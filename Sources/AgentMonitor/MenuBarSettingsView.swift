import SwiftUI
import AgentMonitorCore

/// Popover pane for customising the menu-bar icon, with a live preview using
/// the current usage. Values persist through the same `@AppStorage` keys the
/// label reads, so changes apply immediately.
struct MenuBarSettingsView: View {
    let claude: Usage?
    let codex: CodexUsage?
    let done: () -> Void

    @ObservedObject private var loginItem = LoginItem.shared
    @AppStorage(MenuBarStyle.Key.providers) private var providers = ProviderDisplay.both
    @AppStorage(MenuBarStyle.Key.showLogos) private var showLogos = true
    @AppStorage(MenuBarStyle.Key.showShort) private var showShort = true
    @AppStorage(MenuBarStyle.Key.showWeekly) private var showWeekly = true
    @AppStorage(MenuBarStyle.Key.claudeColor) private var claudeColor = BarColor.terracotta
    @AppStorage(MenuBarStyle.Key.codexColor) private var codexColor = BarColor.primary
    @AppStorage(MenuBarStyle.Key.fill) private var fill = BarFill.remaining
    @AppStorage(MenuBarStyle.Key.warning) private var warning = LimitWarning.at90
    @AppStorage(MenuBarStyle.Key.refreshOnOpen) private var refreshOnOpen = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(title: "Settings", back: done) {
                MenuBarIcon(claude: claude, codex: codex)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08)))
                    .help("Menu bar preview")
            }

            DetailSection(title: "Menu bar") {
                DetailRow(label: "Show") { picker($providers, ProviderDisplay.allCases) { $0.label } }
                // Turning off the last remaining bar is refused.
                toggle("Short window bar", isOn: Binding(get: { showShort },
                                                         set: { if $0 || showWeekly { showShort = $0 } }))
                toggle("Weekly bar", isOn: Binding(get: { showWeekly },
                                                   set: { if $0 || showShort { showWeekly = $0 } }))
                toggle("Provider logos", isOn: $showLogos)
            }

            DetailSection(title: "Appearance") {
                DetailRow(label: "Claude color") { picker($claudeColor, BarColor.allCases) { $0.label } }
                DetailRow(label: "Codex color") { picker($codexColor, BarColor.allCases) { $0.label } }
                DetailRow(label: "Bar fill") { picker($fill, BarFill.allCases) { $0.label } }
                DetailRow(label: "Limit warning") { picker($warning, LimitWarning.allCases) { $0.label } }
            }

            DetailSection(title: "General") {
                toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled },
                                                        set: { loginItem.set($0) }))
                toggle("Refresh when opened", isOn: $refreshOnOpen)
                    .help("Request fresh usage each time the menu opens, instead of waiting for the next scheduled check.")
            }
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        DetailRow(label: title) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private func picker<T: Hashable & Identifiable>(_ selection: Binding<T>, _ options: [T],
                                                     label: @escaping (T) -> String) -> some View {
        Picker("", selection: selection) {
            ForEach(options) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .fixedSize()
    }
}
