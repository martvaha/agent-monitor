import SwiftUI
import AgentMonitorCore

/// Per-provider details: every limit with its exact reset time, where the data
/// comes from and when it last arrived, and a link to the provider's own page.
struct ProviderDetailsView: View {
    let provider: Provider
    @ObservedObject var store: UsageStore
    @ObservedObject var codexStore: CodexStore
    let color: NSColor
    let back: () -> Void

    private func windows(at now: Date) -> [LimitWindow] {
        provider == .claude ? store.usage?.limitWindows(at: now) ?? []
                            : codexStore.usage?.limitWindows(at: now) ?? []
    }

    private var lastSync: Date? { provider == .claude ? store.lastUpdated : codexStore.lastUpdated }

    private var subtitle: String {
        if provider == .codex, let plan = codexStore.usage?.planLabel { return "\(plan) plan" }
        return "Subscription limits"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader(title: "\(provider.name) details", subtitle: subtitle,
                           provider: (provider, color), back: back)
                limits(now: context.date)
                sources(now: context.date)
                Button {
                    NSWorkspace.shared.open(provider.usagePage)
                } label: {
                    Label("Open \(provider == .claude ? "Claude" : "Codex") usage page", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
    }

    private func limits(now: Date) -> some View {
        DetailSection(title: "Limits",
                      footnote: provider == .claude ? "Model-specific limits are not reported." : nil) {
            let windows = windows(at: now)
            if windows.isEmpty {
                DetailRow("Status", "Waiting for usage")
            }
            ForEach(windows) { window in
                DetailRow(window.title, "\(window.percent)% used")
                if let reset = window.resetAt {
                    DetailRow("Resets", TimeText.absolute(reset, now: now))
                }
            }
        }
    }

    private func sources(now: Date) -> some View {
        DetailSection(title: "Data source", footnote: footnote) {
            DetailRow("Limits", provider == .claude ? "Claude account" : "Codex session logs")
            DetailRow("Last sync", lastSync.map { TimeText.relative($0, now: now).capitalizedFirst } ?? "Never")
        }
    }

    private var footnote: String {
        provider == .claude
            ? "Percentages come from Anthropic’s usage endpoint and Claude Code’s status line."
            : "Read from ~/.codex session logs; refreshes whenever Codex runs."
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.font(.system(size: 10, weight: .semibold))
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
