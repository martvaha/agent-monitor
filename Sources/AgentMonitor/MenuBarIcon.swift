import AppKit
import SwiftUI
import AgentMonitorCore

/// Menu-bar label: a pair of slim bars per provider (Claude above, Codex below),
/// each optionally led by the provider's logo at the pair's height. Top bar of
/// each pair is the short window, bottom is weekly. By default fill = remaining,
/// so bars drain as usage rises (like a battery). Options live in `MenuBarStyle`.
struct MenuBarIcon: View {
    let claude: Usage?
    let codex: CodexUsage?

    @AppStorage(MenuBarStyle.Key.providers) private var providers = ProviderDisplay.both
    @AppStorage(MenuBarStyle.Key.showLogos) private var showLogos = true
    @AppStorage(MenuBarStyle.Key.showShort) private var showShort = true
    @AppStorage(MenuBarStyle.Key.showWeekly) private var showWeekly = true
    @AppStorage(MenuBarStyle.Key.claudeColor) private var claudeColor = BarColor.terracotta
    @AppStorage(MenuBarStyle.Key.codexColor) private var codexColor = BarColor.primary
    @AppStorage(MenuBarStyle.Key.fill) private var fill = BarFill.remaining
    @AppStorage(MenuBarStyle.Key.warning) private var warning = LimitWarning.at90

    private var style: MenuBarStyle {
        MenuBarStyle(providers: providers, showLogos: showLogos, showShort: showShort,
                     showWeekly: showWeekly, claudeColor: claudeColor, codexColor: codexColor,
                     fill: fill, warning: warning)
    }

    var body: some View {
        let groups = MenuBarIcon.groups(claude: claude, codex: codex, style: style)
        Image(nsImage: MenuBarIcon.image(groups, style: style))
            .accessibilityLabel(MenuBarIcon.summary(groups))
    }

    struct Group {
        let name: String
        let logo: ProviderLogo
        let color: NSColor
        /// Used percent for the short and weekly windows; nil = unavailable.
        let short: Int?
        let weekly: Int?
    }

    static let warningColor = NSColor(srgbRed: 0.96, green: 0.65, blue: 0.14, alpha: 1)

    static func groups(claude: Usage?, codex: CodexUsage?, style: MenuBarStyle) -> [Group] {
        let claudeGroup = Group(name: "Claude", logo: .anthropic, color: style.claudeColor.nsColor,
                                short: claude?.sessionPercent, weekly: claude?.weekPercent)
        // Windows are shortest-first. A lone long window (e.g. monthly) fills the
        // lower bar and leaves the short-window bar unavailable.
        let windows = codex?.windows ?? []
        let short = windows.first.flatMap { $0.windowMinutes < 600 ? $0 : nil }
        let long = windows.last.flatMap { $0.windowMinutes >= 600 ? $0 : nil }
        let codexGroup = Group(name: "Codex", logo: .openAI, color: style.codexColor.nsColor,
                               short: short?.usedPercent, weekly: long?.usedPercent)
        switch style.providers {
        case .claude: return [claudeGroup]
        case .codex: return [codexGroup]
        case .both: return windows.isEmpty ? [claudeGroup] : [claudeGroup, codexGroup]
        }
    }

    static func summary(_ groups: [Group]) -> String {
        groups.map { g in
            let short = g.short.map { "\($0)% used" } ?? "unavailable"
            let weekly = g.weekly.map { "\($0)% used" } ?? "unavailable"
            return "\(g.name): short window \(short), weekly \(weekly)"
        }.joined(separator: "; ")
    }

    // Geometry in points; half-point steps stay pixel-aligned on Retina.
    private static let barWidth: CGFloat = 20
    private static let dotSize: CGFloat = 3
    private static let dotGap: CGFloat = 2
    private static let logoGap: CGFloat = 2.5
    private static let groupGap: CGFloat = 3

    /// Draws lazily so `labelColor` resolves against the menu bar's current
    /// appearance (light/dark, wallpaper tinting) each time it is rendered.
    static func image(_ groups: [Group], style: MenuBarStyle) -> NSImage {
        // Keep at least one bar per provider even if both toggles are off.
        let rows: [KeyPath<Group, Int?>] = style.showShort || !style.showWeekly
            ? (style.showWeekly ? [\.short, \.weekly] : [\.short]) : [\.weekly]
        let total = rows.count * groups.count
        let bar: CGFloat = total >= 3 ? 2.5 : total == 2 ? 3 : 4
        let barGap: CGFloat = total >= 3 ? 1.5 : 2
        let barsHeight = bar * CGFloat(rows.count) + barGap * CGFloat(rows.count - 1)
        // A logo is never shorter than 6pt, so a single bar per provider still
        // gets a legible mark; the bars centre on it.
        let slot = style.showLogos ? max(barsHeight, 6) : barsHeight
        let height = slot * CGFloat(groups.count) + groupGap * CGFloat(groups.count - 1)
        let threshold = style.warning.threshold
        let warns = threshold.map { t in
            groups.contains { g in rows.contains { (g[keyPath: $0] ?? 0) >= t } }
        } ?? false
        let barsX = style.showLogos ? slot + logoGap : 0
        let width = barsX + barWidth + (warns ? dotGap + dotSize : 0)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            for (i, group) in groups.enumerated() {
                let top = CGFloat(i) * (slot + groupGap)
                if style.showLogos {
                    group.logo.draw(in: CGRect(x: 0, y: top, width: slot, height: slot), color: group.color)
                }
                let barsTop = top + (slot - barsHeight) / 2
                for (j, row) in rows.enumerated() {
                    let value = group[keyPath: row]
                    let rect = CGRect(x: barsX, y: barsTop + CGFloat(j) * (bar + barGap),
                                      width: barWidth, height: bar)
                    drawBar(rect, value: value, color: group.color, fill: style.fill)
                    if let value, let threshold, value >= threshold {
                        let y = min(max(0, rect.midY - dotSize / 2), height - dotSize)
                        warningColor.setFill()
                        NSBezierPath(ovalIn: CGRect(x: rect.maxX + dotGap, y: y,
                                                    width: dotSize, height: dotSize)).fill()
                    }
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawBar(_ rect: CGRect, value: Int?, color: NSColor, fill mode: BarFill) {
        let radius = rect.height / 2
        guard let value else {
            // Unavailable: a dotted track instead of a misleading empty bar.
            let path = NSBezierPath()
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.midY))
            path.line(to: CGPoint(x: rect.maxX - radius, y: rect.midY))
            path.lineWidth = rect.height * 0.6
            path.lineCapStyle = .round
            path.setLineDash([0, rect.height * 1.2], count: 2, phase: 0)
            NSColor.labelColor.withAlphaComponent(0.5).setStroke()
            path.stroke()
            return
        }
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let percent = mode == .remaining ? 100 - value : value
        let fraction = min(max(CGFloat(percent) / 100, 0), 1)
        guard fraction > 0 else { return }
        var fill = rect
        fill.size.width = max(rect.height, rect.width * fraction)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}
