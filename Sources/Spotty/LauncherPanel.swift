import AppKit
import SwiftUI

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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows, hides, places and sizes the launcher panel. The SwiftUI content reports its own
/// height and the panel grows downwards from a fixed top edge.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel = LauncherPanel()
    private let host: NSView
    private var keyMonitor: Any?
    /// The panel's top edge in screen coordinates while it is shown.
    private var top: CGFloat = 0
    private(set) var isShown = false

    /// Called just before the panel appears, so the content can reset itself.
    var willShow: (() -> Void)?
    /// Called once the panel is gone.
    var didHide: (() -> Void)?
    /// Gets every key press while the panel is key; returns true when it handled the key.
    var keyHandler: ((NSEvent) -> Bool)?

    init<Content: View>(content: Content) {
        var onHeight: ((CGFloat) -> Void)?
        let root = content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { onHeight?($0) }
            .frame(maxHeight: .infinity, alignment: .top)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        self.host = host
        super.init()
        panel.contentView = host
        panel.delegate = self
        onHeight = { [weak self] in self?.setHeight($0) }
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard !isShown else { return }
        isShown = true
        willShow?()
        host.layoutSubtreeIfNeeded()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height = max(host.fittingSize.height, 58)
        top = (visible.maxY - visible.height / 3).rounded()
        let frame = NSRect(x: (visible.midX - 280).rounded(), y: top - height, width: 560, height: height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        panel.alphaValue = 0
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: 4), display: false)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().alphaValue = 1
            if !reduceMotion { panel.animator().setFrame(frame, display: true) }
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        removeKeyMonitor()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard !self.isShown else { return }  // shown again mid-fade
                self.panel.orderOut(nil)
                self.didHide?()
            }
        })
    }

    /// Keeps the top edge still: AppKit measures windows from the bottom-left corner.
    private func setHeight(_ height: CGFloat) {
        guard isShown, abs(panel.frame.height - height) > 0.5 else { return }
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - height, width: 560, height: height), display: true)
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
                guard let self, event.window === self.panel, !self.isComposing else { return false }
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
