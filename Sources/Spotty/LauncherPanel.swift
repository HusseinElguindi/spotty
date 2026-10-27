import AppKit
import SwiftUI
import os

/// A borderless panel that takes the keyboard without activating Spotty, so the app you were
/// in stays frontmost and keeps its menu bar.
final class LauncherPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 86),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = Self.everySpace
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// On every Space and over full-screen apps, never in ⌘` cycling.
    static let everySpace: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

    /// After Spotty has run a while, the window server can lose track of the panel belonging to
    /// every Space and pin it to one (seen: pinned to Space 1, so ⌘Space pulled you there).
    /// Setting the behaviour afresh before each show re-registers it; assigning the same value
    /// would be a no-op, hence the round trip through an empty set.
    func rejoinEverySpace() {
        collectionBehavior = []
        collectionBehavior = Self.everySpace
    }
}

/// Shows, hides, places and sizes the launcher panel. The SwiftUI content reports its own
/// height and the panel grows downwards from a fixed top edge.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel = LauncherPanel()
    private let host: NSHostingController<AnyView>
    private var keyMonitor: Any?
    /// The panel's top edge in screen coordinates while it is shown.
    private var top: CGFloat = 0
    private(set) var isShown = false
    /// False only in benchmarks, so the panel shows without taking the keyboard from whoever is typing.
    var takesKey = true

    /// Called just before the panel appears, so the content can reset itself.
    var willShow: (() -> Void)?
    /// Called once the panel is gone.
    var didHide: (() -> Void)?
    /// Gets every key press while the panel is key; returns true when it handled the key.
    var keyHandler: ((NSEvent) -> Bool)?
    /// Told after every key whether an input method is now composing.
    var composingChanged: ((Bool) -> Void)?

    init<Content: View>(content: Content) {
        var onHeight: (() -> Void)?
        let root = content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { _ in onHeight?() }
        let host = NSHostingController(rootView: AnyView(root))
        // The panel sets its own frame from the content's height, so the hosting view mustn't
        // add size constraints of its own. That also leaves its `fittingSize` at zero: measure
        // with `sizeThatFits` instead.
        host.sizingOptions = []
        self.host = host
        super.init()
        panel.contentView = host.view
        panel.delegate = self
        // A backstop: contentChanged() normally resizes before SwiftUI draws.
        onHeight = { [weak self] in self?.contentChanged() }
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard !isShown else { return }
        isShown = true
        willShow?()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // The top edge is fixed for the whole open; every resize hangs the window from it.
        top = (visible.maxY - visible.height / 3).rounded()
        // Measured now, for the content willShow just reset, so the window opens at the right height.
        let height = max(contentHeight, 58)
        panel.setFrame(NSRect(x: (visible.midX - 280).rounded(), y: top - height, width: 560, height: height),
                       display: false)

        // Appears at once, at its final size: no fade, no movement. Never activates Spotty.
        panel.rejoinEverySpace()
        focusField()
        orderFront()
        healSpace()
        installKeyMonitor()
    }

    private func orderFront() {
        if takesKey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
    }

    private static let spaceLog = Logger(subsystem: "com.hus.spotty", category: "spaces")

    /// The window server sometimes keeps the panel on one Space despite `canJoinAllSpaces`, and
    /// then ⌘Space opens it on that Space, out of sight. Checked after every show, so it heals
    /// whatever the trigger: first by re-registering for every Space, then by moving the panel to
    /// the Space you are on.
    private func healSpace() {
        guard !panel.isOnActiveSpace else { return }
        Self.spaceLog.error("Panel opened off the active Space; re-registering it for every Space")
        panel.orderOut(nil)
        panel.rejoinEverySpace()
        orderFront()
        guard !panel.isOnActiveSpace else { return }
        Self.spaceLog.error("Still off the active Space; moving it to the active Space")
        panel.orderOut(nil)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        orderFront()
        if !panel.isOnActiveSpace { Self.spaceLog.fault("Panel could not be brought to the active Space") }
        // Back to every Space for next time; the window stays where it now is while shown.
        panel.collectionBehavior = LauncherPanel.everySpace
    }

    /// Creates the window's backing and lays out the content once, invisibly, so the first ⌘Space
    /// costs no more than later ones.
    func prewarm() {
        guard !isShown else { return }
        willShow?()
        panel.setFrame(NSRect(x: 0, y: 0, width: 560, height: max(contentHeight, 58)), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.contentView?.displayIfNeeded()
        focusField()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    /// Makes the search field first responder right away, rather than a run-loop turn later
    /// through SwiftUI's focus state, so a key typed straight after ⌘Space isn't lost.
    private func focusField() {
        guard !(panel.firstResponder is NSTextView) else { return }
        func field(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap(field(in:)).first
        }
        if let field = panel.contentView.flatMap(field(in:)) { panel.makeFirstResponder(field) }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        removeKeyMonitor()
        // Gone at once, so it stops taking input immediately. The field stays first responder in
        // the hidden window, so it takes typing the instant the panel next becomes key.
        panel.orderOut(nil)
        didHide?()
    }

    var contentHeight: CGFloat {
        host.sizeThatFits(in: CGSize(width: 560, height: CGFloat.greatestFiniteMagnitude)).height.rounded(.up)
    }

    /// Resizes the window to the content at once, before SwiftUI draws the new tray, and keeps the
    /// top edge still (AppKit measures windows from the bottom-left corner). Call it whenever the
    /// content changes; it is cheap when nothing moved.
    func contentChanged() {
        guard isShown else { return }
        let height = max(contentHeight, 58)
        guard abs(panel.frame.height - height) > 0.5 || abs(panel.frame.maxY - top) > 0.5 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            panel.setFrame(NSRect(x: panel.frame.minX, y: top - height, width: 560, height: height), display: true)
        }
        panel.invalidateShadow()
    }

    /// True while an input method is composing, when every key belongs to it.
    var isComposing: Bool {
        (panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                // A key pressed straight after ⌘Space can arrive before macOS has tied it to the
                // panel, with no window at all. While the panel is up it is the panel's key; only
                // keys for another window (Settings) are left alone.
                guard let self, self.isShown, event.window == nil || event.window === self.panel else { return false }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.composingChanged?(self.isComposing)
                }
                guard !self.isComposing else { return false }
                return self.keyHandler?(event) == true
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // Clicking anywhere else takes key status away, which closes the panel.
    func windowDidResignKey(_ notification: Notification) { hide() }
}

