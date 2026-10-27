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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        #if DEBUG
        // Tests that show panels on someone's screen keep them invisible.
        if ProcessInfo.processInfo.environment["SPOTTY_INVISIBLE"] != nil { alphaValue = 0 }
        #endif
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

}

/// Shows, hides, places and sizes the launcher panel. The SwiftUI content reports its own
/// height and the panel grows downwards from a fixed top edge.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    /// Replaced by `rebuild` when the window server stops showing it on every Space.
    private(set) var panel = LauncherPanel()
    /// Set when the displays wake or change; the next show starts with a fresh window.
    private var needsRebuild = false
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
        // After the displays sleep and wake (and reconfigure), the window server can leave the
        // panel on one Space for good, whatever its collection behaviour says; seen at 05:51Z on
        // 27 Oct, when re-registering it and moving it both failed. A fresh window is always fine.
        for (center, name) in [(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
                               (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification)] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.needsRebuild = true }
            }
        }
        // A backstop: contentChanged() normally resizes before SwiftUI draws.
        onHeight = { [weak self] in self?.contentChanged() }
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard !isShown else { return }
        isShown = true
        if needsRebuild { rebuild("the displays changed or woke") }
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
        focusField()
        orderFront()
        if !panel.isOnActiveSpace {
            // Stuck on another Space despite all that: replace the window and show the new one.
            let frame = panel.frame
            rebuild("the panel opened off the active Space")
            panel.setFrame(frame, display: false)
            focusField()
            orderFront()
        }
        SpaceProbe.log(panel)
        installKeyMonitor()
    }

    private static let spaceLog = Logger(subsystem: "com.hus.spotty", category: "spaces")

    /// Moves the content into a fresh panel and lets the old window go.
    private func rebuild(_ reason: String) {
        Self.spaceLog.error("Rebuilding the panel: \(reason, privacy: .public)")
        needsRebuild = false
        let old = panel
        old.delegate = nil  // its resigning key must not close the new one
        old.orderOut(nil)
        old.contentView = nil
        panel = LauncherPanel()
        panel.contentView = host.view
        panel.delegate = self
    }

    private func orderFront() {
        if takesKey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
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


/// Logs which Space the panel really landed on, asked of the window server directly, since
/// AppKit's own answer can be wrong. Uses private read-only CoreGraphics calls looked up at run
/// time; if they are missing it logs nothing. `log show --predicate 'subsystem == "com.hus.spotty"
/// AND category == "spaces"'` lists the lines.
@MainActor
enum SpaceProbe {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias SpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let log = Logger(subsystem: "com.hus.spotty", category: "spaces")
    private static let calls: (MainConnection, ActiveSpace, SpacesForWindows)? = {
        guard let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let main = dlsym(cg, "CGSMainConnectionID"), let active = dlsym(cg, "CGSGetActiveSpace"),
              let spaces = dlsym(cg, "CGSCopySpacesForWindows")
        else { return nil }
        return (unsafeBitCast(main, to: MainConnection.self), unsafeBitCast(active, to: ActiveSpace.self),
                unsafeBitCast(spaces, to: SpacesForWindows.self))
    }()

    static func log(_ window: NSWindow) {
        guard let (main, active, spacesFor) = calls else { return }
        let connection = main()
        let current = active(connection)
        let spaces = spacesFor(connection, 7, [window.windowNumber] as CFArray)?.takeRetainedValue() as? [UInt64] ?? []
        if spaces.contains(current) {
            log.notice("Panel on the active Space \(current); its Spaces \(spaces, privacy: .public)")
        } else {
            log.error("Panel NOT on the active Space \(current); its Spaces \(spaces, privacy: .public)")
        }
    }
}
