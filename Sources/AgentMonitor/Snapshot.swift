import SwiftUI
import AgentMonitorCore

#if DEBUG
/// Renders the popover to PNGs for visual review: `AgentMonitor --snapshot <dir>`.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = args[i + 1]

        let states: [(String, UsageStore, CodexStore)] = [
            ("low", store(34, week: 51), codexStore(20)),
            ("mid", store(72, week: 88), codexStore(55)),
            ("high", store(94, week: 96), codexStore(91)),
            ("waiting", UsageStore(), CodexStore()),
        ]
        for (name, st, cx) in states {
            render(MenuBarView(store: st, codexStore: cx), name: "popover-\(name)", dir: dir)
        }
        let (_, st, cx) = states[0]
        render(MenuBarView(store: st, codexStore: cx, pane: .settings), name: "popover-settings", dir: dir)
        render(MenuBarView(store: st, codexStore: cx, pane: .details(.claude)), name: "popover-details-claude", dir: dir)
        render(MenuBarView(store: st, codexStore: cx, pane: .details(.codex)), name: "popover-details-codex", dir: dir)
        writeIcons(to: dir)
        return true
    }

    /// Hosts the view in an offscreen window so native controls (pickers,
    /// switches) render, which `ImageRenderer` cannot draw. Light and dark.
    private static func render<V: View>(_ view: V, name: String, dir: String) {
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingView(rootView: view.background(.background))
            host.appearance = NSAppearance(named: appearance)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(mode).png"))
                FileHandle.standardError.write(Data("wrote \(name)-\(mode).png\n".utf8))
            }
        }
    }

    /// Menu-bar icon states on light and dark bars, scaled up for review.
    private static func writeIcons(to dir: String) {
        let soon = Date().addingTimeInterval(3600)
        let codex = CodexUsage(windows: [
            CodexWindow(usedPercent: 62, resetsAt: soon, windowMinutes: 300),
            CodexWindow(usedPercent: 28, resetsAt: soon, windowMinutes: 10080),
        ], observedAt: Date())
        let monthly = CodexUsage(windows: [
            CodexWindow(usedPercent: 40, resetsAt: soon, windowMinutes: 43800),
        ], observedAt: Date())
        let usage = Usage(sessionPercent: 15, sessionResetAt: soon, weekPercent: 46)
        var noLogos = MenuBarStyle(); noLogos.showLogos = false
        var weeklyOnly = MenuBarStyle(); weeklyOnly.showShort = false
        var custom = MenuBarStyle(); custom.claudeColor = .blue; custom.codexColor = .green
        custom.fill = .used
        let states: [(String, Usage?, CodexUsage?, MenuBarStyle)] = [
            ("both", usage, codex, MenuBarStyle()),
            ("claude", usage, nil, MenuBarStyle()),
            ("near", Usage(sessionPercent: 93, sessionResetAt: soon, weekPercent: 46), codex, MenuBarStyle()),
            ("monthly", Usage(sessionPercent: 15, sessionResetAt: soon, weekPercent: nil), monthly, MenuBarStyle()),
            ("waiting", nil, nil, MenuBarStyle()),
            ("nologos", usage, codex, noLogos),
            ("weekly", usage, codex, weeklyOnly),
            ("custom", usage, codex, custom),
        ]
        let scale: CGFloat = 8
        for (name, claude, cx, style) in states {
            let icon = MenuBarIcon.image(MenuBarIcon.groups(claude: claude, codex: cx, style: style),
                                         style: style)
            for (mode, appearance, bg) in [("light", NSAppearance.Name.aqua, NSColor(white: 0.93, alpha: 1)),
                                           ("dark", .darkAqua, NSColor(white: 0.12, alpha: 1))] {
                let size = NSSize(width: (icon.size.width + 8) * scale, height: 22 * scale)
                let out = NSImage(size: size)
                NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                    out.lockFocus()
                    bg.setFill()
                    NSRect(origin: .zero, size: size).fill()
                    let rect = NSRect(x: 4 * scale, y: (22 - icon.size.height) / 2 * scale,
                                      width: icon.size.width * scale, height: icon.size.height * scale)
                    icon.draw(in: rect)
                    out.unlockFocus()
                }
                if let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(dir)/icon-\(name)-\(mode).png"))
                }
            }
        }
    }

    private static func store(_ percent: Int, week: Int?) -> UsageStore {
        let s = UsageStore()
        s.injectSample(Usage(
            sessionPercent: percent,
            sessionResetAt: Date().addingTimeInterval(2 * 3600),
            weekPercent: week,
            weekResetAt: Date().addingTimeInterval(3 * 24 * 3600)
        ))
        return s
    }

    private static func codexStore(_ percent: Int) -> CodexStore {
        let s = CodexStore()
        s.injectSample(CodexUsage(
            windows: [CodexWindow(
                usedPercent: percent,
                resetsAt: Date().addingTimeInterval(12 * 24 * 3600),
                windowMinutes: 43800
            )],
            planType: "team",
            observedAt: Date()
        ))
        return s
    }
}
#endif
