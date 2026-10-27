import AppKit
import LauncherCore
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
        // Moved to whichever Space is active each time it is shown, as Maccy and Ice do, rather
        // than joining every Space: macOS sometimes forgot a hidden every-Space panel's membership
        // and left it on one Space, so ⌘Space opened it out of sight.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
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
/// height and the panel grows downwards from a fixed top edge. Dragging the panel moves that
/// edge, with guides to snap back to the standard spot, and the next open keeps the new spot.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    /// Replaced by `rebuild` when, after a display wake, it still lands off the active Space.
    private(set) var panel = LauncherPanel()
    /// Set when the displays wake or change; the next show starts with a fresh window.
    private var needsRebuild = false
    private let host: NSHostingController<AnyView>
    private var keyMonitor: Any?
    /// Clicks in other apps while the panel is up, and the Space or screen going away. Closing
    /// otherwise relies on the panel losing key status, which never happens if it never got it.
    private(set) var outsideClickMonitor: Any?
    /// The panel's top edge in screen coordinates while it is shown.
    private var top: CGFloat = 0
    /// Where the panel opens, saved across launches. Kept here, not on the window, so a rebuild keeps it.
    private var placement = PanelController.savedPlacement
    /// The visible area of the screen the panel is shown on.
    private var visible = NSRect.zero
    /// The pointer and the panel's centre and top edge, all in screen points, when a drag began.
    private var dragStart: (pointer: NSPoint, midX: CGFloat, top: CGFloat)?
    private let guides = PanelGuides()
    /// Room kept below the top edge for the tallest tray (six rows and a why line), so dragging
    /// the panel low never pushes results off the screen.
    private static let tallest: CGFloat = 340
    private(set) var isShown = false
    /// False only in benchmarks, so the panel shows without taking the keyboard from whoever is typing.
    var takesKey = true

    /// Called just before the panel appears, so the content can refresh itself.
    var willShow: (() -> Void)?
    /// Called once the panel is gone.
    var didHide: (() -> Void)?
    /// Gets every key press while the panel is key; returns true when it handled the key.
    var keyHandler: ((NSEvent) -> Bool)?
    /// Told after every key whether an input method is now composing.
    var composingChanged: ((Bool) -> Void)?

    init<Content: View>(content: Content) {
        var onHeight: (() -> Void)?
        var onDrag: ((DragGesture.Value?) -> Void)?
        let root = content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { _ in onHeight?() }
            // Anywhere but the field's text moves the panel; a click without movement still
            // reaches the row or button under it.
            .contentShape(.rect(cornerRadius: 16))
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { onDrag?($0) }
                .onEnded { _ in onDrag?(nil) })
        let host = NSHostingController(rootView: AnyView(root))
        // The panel sets its own frame from the content's height, so the hosting view mustn't
        // add size constraints of its own. That also leaves its `fittingSize` at zero: measure
        // with `sizeThatFits` instead.
        host.sizingOptions = []
        self.host = host
        super.init()
        panel.contentView = host.view
        panel.delegate = self
        // Never leave the panel up on a Space you have left, or over a sleeping screen.
        for (name, event) in [(NSWorkspace.activeSpaceDidChangeNotification, "Space switch"),
                              (NSWorkspace.screensDidSleepNotification, "screens sleep")] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    SpaceProbe.log(self.panel, event)
                    self.hide()
                }
            }
        }
        // A guard kept from the every-Space days: after the displays wake or change, the next show
        // is checked, and the window replaced if it still lands off the active Space.
        for (center, name, event) in [
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, "screen change"),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification, "screens wake"),
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    SpaceProbe.log(self.panel, event)
                    self.needsRebuild = true
                }
            }
        }
        // A backstop: contentChanged() normally resizes before SwiftUI draws.
        onHeight = { [weak self] in self?.contentChanged() }
        onDrag = { [weak self] value in
            guard let self else { return }
            if let value { self.dragged(from: value.startLocation, to: value.location) } else { self.endDrag() }
        }
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard !isShown else { return }
        isShown = true
        let afterWake = needsRebuild
        needsRebuild = false
        willShow?()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // The top edge is fixed for the whole open, unless dragged; every resize hangs the window from it.
        let midX: CGFloat
        (midX, top) = placement.resolve(in: visible, width: 560, tallest: Self.tallest)
        // Measured now, for the content willShow just reset, so the window opens at the right height.
        let height = max(contentHeight, 58)
        panel.setFrame(NSRect(x: midX - 280, y: top - height, width: 560, height: height), display: false)

        // Appears at once, at its final size: no fade, no movement. Never activates Spotty.
        SpaceProbe.log(panel, "before show")
        focusField()
        orderFront()
        SpaceProbe.log(panel, "after show")
        if afterWake { checkSpaceSoon() }
        installKeyMonitor()
        // A click in any other app closes the panel. Mouse-down monitors need no permission.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        if takesKey {
            // If macOS didn't hand the panel the keyboard, Esc and clicking elsewhere would do
            // nothing; ask once more on the next turn.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isShown, !self.panel.isKeyWindow else { return }
                Self.spaceLog.error("Panel shown without key status; making it key again")
                self.panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    private static let spaceLog = Logger(subsystem: "com.hus.spotty", category: "spaces")

    /// After a display wake, looks again 100 ms after showing (a window just ordered in can read
    /// as on no Space for a moment) and replaces the window only if it is still off the active Space.
    private func checkSpaceSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.isShown, SpaceProbe.isOnActiveSpace(self.panel) == false else { return }
            let frame = self.panel.frame
            self.rebuild("still off the active Space 100 ms after showing, after a display wake")
            self.panel.setFrame(frame, display: false)
            self.focusField()
            self.orderFront()
            SpaceProbe.log(self.panel, "after rebuild")
        }
    }

    /// Moves the content into a fresh panel and lets the old window go.
    private func rebuild(_ reason: String) {
        Self.spaceLog.error("Rebuilding the panel: \(reason, privacy: .public)")
        needsRebuild = false
        let old = panel
        old.delegate = nil  // its resigning key must not close the new one
        old.orderOut(nil)
        old.contentView = nil
        old.close()
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
    /// Also selects the field's text, so a query kept from the last open is replaced by typing.
    private func focusField() {
        func field(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap(field(in:)).first
        }
        if !(panel.firstResponder is NSTextView), let field = panel.contentView.flatMap(field(in:)) {
            panel.makeFirstResponder(field)
        }
        (panel.firstResponder as? NSTextView)?.selectAll(nil)
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        endDrag()
        removeKeyMonitor()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        // Gone at once, so it stops taking input immediately. The field stays first responder in
        // the hidden window, so it takes typing the instant the panel next becomes key.
        panel.orderOut(nil)
        SpaceProbe.log(panel, "hidden")
        if panel.isVisible {
            // A window the window server has broken can ignore orderOut, leaving it on screen
            // while Spotty thinks it is hidden; then ⌘Space shows instead of closing. Discard it.
            rebuild("the panel stayed visible after hiding")
        }
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

    // MARK: Dragging

    /// Moves the panel so the point grabbed stays under the pointer, sticking to a guide when it
    /// comes close. Both points are in the content's own coordinates, top-left origin, measured
    /// where the panel is now; `start` is where the mouse went down.
    private func dragged(from start: CGPoint, to location: CGPoint) {
        guard isShown else { return }
        let frame = panel.frame
        func onScreen(_ p: CGPoint) -> NSPoint { NSPoint(x: frame.minX + p.x, y: frame.maxY - p.y) }
        let pointer = onScreen(location)
        if dragStart == nil {
            // The panel hasn't moved yet, so the mouse-down point converts as it is.
            dragStart = (onScreen(start), frame.midX, top)
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame == visible }) ?? panel.screen {
                guides.show(on: screen, visible: visible, width: 560, tallest: Self.tallest, below: panel)
            }
        }
        guard let start = dragStart else { return }
        let (placed, snapped) = PanelPlacement.dragged(midX: start.midX + pointer.x - start.pointer.x,
                                                       top: start.top + pointer.y - start.pointer.y,
                                                       in: visible, width: 560, tallest: Self.tallest)
        placement = placed
        guides.update(snapped: snapped)
        let midX: CGFloat
        (midX, top) = placed.resolve(in: visible, width: 560, tallest: Self.tallest)
        let origin = NSPoint(x: midX - 280, y: top - frame.height)
        guard origin != frame.origin else { return }
        panel.setFrameOrigin(origin)
    }

    private func endDrag() {
        guard dragStart != nil else { return }
        dragStart = nil
        guides.hide()
        Self.savedPlacement = placement
    }

    private static let placementKey = "panelPlacement"

    /// Where the panel opens; the standard spot unless it was dragged somewhere else.
    private static var savedPlacement: PanelPlacement {
        get {
            UserDefaults.standard.data(forKey: placementKey)
                .flatMap { try? JSONDecoder().decode(PanelPlacement.self, from: $0) } ?? .standard
        }
        set {
            if newValue == .standard {
                UserDefaults.standard.removeObject(forKey: placementKey)
            } else if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: placementKey)
            }
        }
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


/// Logs which Space the panel is really on, asked of the window server directly, since AppKit's
/// own answer can be wrong; also the active Space and its changes. Only Space ids, never typed
/// text. Uses private read-only CoreGraphics calls looked up at run time; if they are missing it
/// logs nothing. `/usr/bin/log show --predicate 'subsystem == "com.hus.spotty" AND
/// category == "spaces"'` lists the lines (plain `log` is a zsh builtin).
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
    /// The active Space at the last log line, to report a switch as from and to.
    private static var lastActive: UInt64?

    private static func read(_ window: NSWindow) -> (active: UInt64, spaces: [UInt64])? {
        guard let (main, active, spacesFor) = calls else { return nil }
        let connection = main()
        let spaces = spacesFor(connection, 7, [window.windowNumber] as CFArray)?.takeRetainedValue() as? [UInt64] ?? []
        return (active(connection), spaces)
    }

    /// The window server's answer; nil when it can't be asked.
    static func isOnActiveSpace(_ window: NSWindow) -> Bool? {
        read(window).map { $0.spaces.contains($0.active) }
    }

    static func log(_ window: NSWindow, _ event: String) {
        guard let (active, spaces) = read(window) else { return }
        let from = lastActive.map(String.init) ?? "?"
        lastActive = active
        if event == "after show" && !spaces.contains(active) {
            log.error("\(event, privacy: .public): panel NOT on the active Space \(active); its Spaces \(spaces, privacy: .public)")
        } else {
            log.notice("\(event, privacy: .public): active Space \(from, privacy: .public) -> \(active); panel's Spaces \(spaces, privacy: .public)")
        }
    }
}
