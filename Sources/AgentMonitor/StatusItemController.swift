import AppKit
import Combine
import SwiftUI

/// Owns the menu-bar item and its Golden Gate expanded-interface session.
/// The explicitly sized panel replaces `MenuBarExtra(.window)`,
/// whose panel keeps the glass backdrop and shadow of its previous size when the
/// content resizes (switching panes left a ghost frame around Settings). Here the
/// panel is resized explicitly, anchored to its top edge.
@MainActor
final class StatusItemController: NSObject, @MainActor NSStatusItemExpandedInterfaceDelegate {
    private let store: UsageStore
    private let codexStore: CodexStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = StatusPanel()
    private var cancellables: Set<AnyCancellable> = []
    private var panelTop: CGFloat?
    private var pendingSize: CGSize?
    private var resizeScheduled = false

    init(store: UsageStore, codexStore: CodexStore) {
        self.store = store
        self.codexStore = codexStore
        super.init()

        // AppKit owns toggling, selection highlight and menu-bar keyboard tracking.
        statusItem.expandedInterfaceDelegate = self
        panel.onCancel = { [weak self] in self?.close() }
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak self] _ in self?.close() }
            .store(in: &cancellables)

        // The label redraws on new usage or any style change in Settings.
        store.$usage.map { _ in () }
            .merge(with: codexStore.$usage.map { _ in () },
                   NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateLabel() }
            .store(in: &cancellables)
        updateLabel()
    }

    private func updateLabel() {
        guard let button = statusItem.button else { return }
        let style = MenuBarStyle.stored
        let groups = MenuBarIcon.groups(claude: store.usage, codex: codexStore.usage, style: style)
        button.image = MenuBarIcon.image(groups, style: style)
        button.setAccessibilityLabel(MenuBarIcon.summary(groups))
    }

    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        open()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        hidePanel()
    }

    private func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else {
            close()
            return
        }
        // A fresh view per opening starts on the main pane and runs its onAppear refresh.
        let content = MenuBarView(store: store, codexStore: codexStore)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { [weak self] size in
                self?.resize(to: size)
            }
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        // From here the panel follows the geometry callback, not Auto Layout.
        host.sizingOptions = []
        panel.setContent(host)

        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = max(visible.minX + 8, min(anchor.minX, visible.maxX - size.width - 8))
        // Golden Gate's status items share a menu-bar window. Anchor to the
        // actual button bounds, with no extra gap below the menu bar.
        let top = anchor.minY
        panelTop = top
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height),
                       display: true)
        panel.layoutContent()
        panel.makeKeyAndOrderFront(nil)
    }

    private func resize(to size: CGSize) {
        guard panel.isVisible, size.width > 0, size.height > 0 else { return }
        pendingSize = size
        guard !resizeScheduled else { return }
        resizeScheduled = true

        // Geometry callbacks arrive during SwiftUI layout. Resizing the window
        // there can draw the new backdrop around content from the previous layout.
        // Apply the latest measurement once that layout has finished.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeScheduled = false
            guard self.panel.isVisible, let size = self.pendingSize, let top = self.panelTop else { return }
            self.pendingSize = nil
            guard size != self.panel.frame.size else { return }
            self.panel.setFrame(NSRect(x: self.panel.frame.minX, y: top - size.height,
                                      width: size.width, height: size.height), display: false)
            self.panel.layoutContent()
            self.panel.displayIfNeeded()
            self.panel.invalidateShadow()
        }
    }

    private func close() {
        // Let AppKit end tracking before the delegate tears down the panel.
        statusItem.expandedInterfaceSession?.cancel()
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        panel.setContent(nil)
        panelTop = nil
        pendingSize = nil
    }
}

/// Borderless panel with the system popover backdrop. Non-activating, so opening
/// it doesn't pull the app forward, but it can still take key for shortcuts.
private final class StatusPanel: NSPanel {
    var onCancel: (() -> Void)?
    private let surface = NSView()
    private let backdrop = NSGlassEffectView()
    private var hostedContent: NSView?

    init() {
        let cornerRadius: CGFloat = 16
        backdrop.cornerRadius = cornerRadius
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Glass rounds its effect, but not the window's backing surface. Clip
        // that surface too, so its corners and window shadow follow the glass.
        surface.wantsLayer = true
        surface.layer?.cornerRadius = cornerRadius
        surface.layer?.cornerCurve = .continuous
        surface.layer?.masksToBounds = true
        contentView = surface
        backdrop.frame = surface.bounds
        backdrop.autoresizingMask = [.width, .height]
        surface.addSubview(backdrop)
    }

    override var canBecomeKey: Bool { true }

    /// Escape closes the panel; panes with a back button handle it first.
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    func setContent(_ view: NSView?) {
        hostedContent = view
        if let view {
            view.frame = backdrop.bounds
            view.autoresizingMask = [.width, .height]
        }
        backdrop.contentView = view
    }

    /// Keep the hosting view and the glass at the same size on every pane change.
    func layoutContent() {
        backdrop.frame = surface.bounds
        hostedContent?.frame = backdrop.bounds
        surface.layoutSubtreeIfNeeded()
        hostedContent?.layoutSubtreeIfNeeded()
    }
}
