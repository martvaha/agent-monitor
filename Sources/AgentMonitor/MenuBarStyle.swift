import AppKit

/// User-customisable menu-bar icon options, persisted in UserDefaults via
/// `@AppStorage` (keys below) so the label and the settings pane stay in sync.
struct MenuBarStyle: Equatable {
    var providers: ProviderDisplay = .both
    var showLogos = true
    var showShort = true
    var showWeekly = true
    var claudeColor: BarColor = .terracotta
    var codexColor: BarColor = .primary
    var fill: BarFill = .remaining
    var warning: LimitWarning = .at90

    enum Key {
        static let providers = "menuBar.providers"
        static let showLogos = "menuBar.showLogos"
        static let showShort = "menuBar.showShort"
        static let showWeekly = "menuBar.showWeekly"
        static let claudeColor = "menuBar.claudeColor"
        static let codexColor = "menuBar.codexColor"
        static let fill = "menuBar.fill"
        static let warning = "menuBar.warning"
        static let refreshOnOpen = "general.refreshOnOpen"
    }

    /// The style as persisted by Settings, for code outside SwiftUI's `@AppStorage`.
    static var stored: MenuBarStyle {
        let defaults = UserDefaults.standard
        func value<T: RawRepresentable<String>>(_ key: String, _ fallback: T) -> T {
            defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        let base = MenuBarStyle()
        return MenuBarStyle(providers: value(Key.providers, base.providers),
                            showLogos: flag(Key.showLogos), showShort: flag(Key.showShort),
                            showWeekly: flag(Key.showWeekly),
                            claudeColor: value(Key.claudeColor, base.claudeColor),
                            codexColor: value(Key.codexColor, base.codexColor),
                            fill: value(Key.fill, base.fill), warning: value(Key.warning, base.warning))
    }
}

enum ProviderDisplay: String, CaseIterable, Identifiable {
    /// Claude, plus Codex beneath once it has data.
    case both, claude, codex
    var id: Self { self }
    var label: String {
        switch self {
        case .both: return "Both"
        case .claude: return "Claude only"
        case .codex: return "Codex only"
        }
    }
}

enum BarFill: String, CaseIterable, Identifiable {
    case remaining, used
    var id: Self { self }
    var label: String { self == .remaining ? "Remaining" : "Used" }
}

enum LimitWarning: String, CaseIterable, Identifiable {
    case off, at80, at90
    var id: Self { self }
    var label: String {
        switch self {
        case .off: return "Off"
        case .at80: return "At 80%"
        case .at90: return "At 90%"
        }
    }
    var threshold: Int? {
        switch self {
        case .off: return nil
        case .at80: return 80
        case .at90: return 90
        }
    }
}

enum BarColor: String, CaseIterable, Identifiable {
    /// `primary` follows the menu bar: black on light, white on dark.
    case terracotta, primary, blue, green, purple, orange
    var id: Self { self }
    var label: String {
        switch self {
        case .terracotta: return "Terracotta"
        case .primary: return "Black / White"
        case .blue: return "Blue"
        case .green: return "Green"
        case .purple: return "Purple"
        case .orange: return "Orange"
        }
    }
    var nsColor: NSColor {
        switch self {
        case .terracotta: return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        case .primary: return .labelColor
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .purple: return .systemPurple
        case .orange: return .systemOrange
        }
    }
}
