import SwiftUI
import AgentMonitorCore

/// Building blocks shared by the popover panes, styled after macOS menus and
/// System Settings: 13pt body text, secondary captions, hairline separators and
/// hover highlights instead of bordered buttons.

enum Provider: Hashable {
    case claude, codex

    var name: String { self == .claude ? "Claude Code" : "Codex" }
    var logo: ProviderLogo { self == .claude ? .anthropic : .openAI }
    var usagePage: URL {
        URL(string: self == .claude ? "https://claude.ai/settings/usage"
                                    : "https://chatgpt.com/codex/settings/usage")!
    }
}

/// One rate-limit window as the popover shows it, independent of provider.
struct LimitWindow: Identifiable {
    let title: String
    let percent: Int
    let resetAt: Date?
    var id: String { title }
}

/// An elapsed window shows as empty with no countdown; the next one starts with use.
extension Usage {
    func limitWindows(at now: Date) -> [LimitWindow] {
        var windows = [LimitWindow(title: "Short window (5h)", percent: sessionPercent(at: now),
                                   resetAt: sessionResetAt > now ? sessionResetAt : nil)]
        if let weekPercent = weekPercent(at: now) {
            windows.append(LimitWindow(title: "Weekly", percent: weekPercent,
                                       resetAt: weekResetAt.flatMap { $0 > now ? $0 : nil }))
        }
        return windows
    }
}

extension CodexUsage {
    func limitWindows(at now: Date) -> [LimitWindow] {
        windows.map { window in
            let title = window.label == "5-hour" ? "Short window (5h)" : window.label
            return LimitWindow(title: title, percent: window.usedPercent(at: now),
                               resetAt: window.isElapsed(at: now) ? nil : window.resetsAt)
        }
    }

    /// "team" → "Team"; nil when Codex did not report a plan.
    var planLabel: String? { planType.map { $0.prefix(1).uppercased() + $0.dropFirst() } }
}

enum TimeText {
    /// "just now", "4 minutes ago".
    static func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "Today 18:23", "Tomorrow 09:00", "Thu 14:00", "12 Nov 14:00".
    static func absolute(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow \(time)" }
        if date.timeIntervalSince(now) < 6 * 24 * 3600 {
            return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        }
        return "\(date.formatted(.dateTime.day().month(.abbreviated))) \(time)"
    }
}

/// The provider mark at text size, coloured like its menu-bar bars.
struct ProviderLogoView: View {
    let provider: Provider
    let color: NSColor
    var size: CGFloat = 20

    var body: some View {
        // Drawn lazily so dynamic colours (labelColor) follow light/dark mode.
        Image(nsImage: NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            provider.logo.draw(in: rect, color: color)
            return true
        })
        .accessibilityHidden(true)
    }
}

/// Title + used percent, a slim capsule meter, then remaining + live countdown.
/// The meter fills like the menu-bar bars: remaining (drains) or used (grows).
struct LimitMeter: View {
    let window: LimitWindow
    let tint: Color
    var fill: BarFill = .remaining

    private var shown: Int { fill == .remaining ? 100 - window.percent : window.percent }
    private var fraction: Double { min(max(Double(shown) / 100, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                Spacer()
                Text("\(window.percent)% used")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(tint)
                        .frame(width: shown <= 0 ? 0 : max(5, geo.size.width * fraction))
                        .animation(.easeInOut(duration: 0.5), value: fraction)
                }
            }
            .frame(height: 5)

            HStack(alignment: .firstTextBaseline) {
                Text("\(max(0, 100 - window.percent))% remaining")
                Spacer()
                if let resetAt = window.resetAt {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text("Resets in \(ResetTime.countdownLong(to: resetAt, from: context.date))")
                    }
                }
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A full-width row that leads to another pane: "Details ›".
struct NavigationRow: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.1 : 0.05)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A menu-style command: SF Symbol, title and right-aligned shortcut, with the
/// rounded hover highlight of an NSMenu item.
struct MenuRow: View {
    let title: String
    let symbol: String
    let key: KeyEquivalent
    let action: () -> Void
    @State private var hovering = false

    private var shortcut: String {
        switch key {
        case ",": return "⌘ ,"
        default: return "⌘ \(String(key.character).uppercased())"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .foregroundStyle(hovering ? Color.white : .secondary)
                Text(title)
                Spacer()
                Text(shortcut)
                    .foregroundStyle(hovering ? Color.white.opacity(0.8) : Color.secondary)
            }
            .font(.system(size: 13))
            .foregroundStyle(hovering ? Color.white : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hovering ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .onHover { hovering = $0 }
    }
}

/// Back chevron + title row at the top of a secondary pane.
struct PaneHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var provider: (Provider, NSColor)?
    let back: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
            .help("Back")
            if let (provider, color) = provider {
                ProviderLogoView(provider: provider, color: color, size: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
    }
}

extension PaneHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, provider: (Provider, NSColor)? = nil,
         back: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, provider: provider, back: back) { EmptyView() }
    }
}

/// A titled group of label/value rows separated by hairlines, with an optional
/// footnote — the popover equivalent of a grouped System Settings section.
struct DetailSection<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 6)
            content()
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }
}

/// Label on the left, value or control on the right, hairline above.
struct DetailRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: () -> Value

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(label)
                Spacer(minLength: 12)
                value()
                    .multilineTextAlignment(.trailing)
            }
            .font(.system(size: 13))
            .frame(minHeight: 20)
            .padding(.vertical, 5)
        }
    }
}

extension DetailRow where Value == Text {
    init(_ label: String, _ value: String) {
        self.init(label: label) { Text(value) }
    }
}

/// A warning line with an optional action, used for stale data and Keychain prompts.
struct Callout: View {
    let message: String
    var symbol = "exclamationmark.triangle.fill"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.yellow)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .help(message)
    }
}
