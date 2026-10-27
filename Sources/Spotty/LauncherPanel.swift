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

        // Appears at once, at its final size: no fade, no movement. A zero-length animation
        // also cancels a close fade still in flight.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.ignoresMouseEvents = false
        if takesKey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        installKeyMonitor()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        removeKeyMonitor()
        // Done taking input the moment closing starts, not when the fade ends.
        panel.ignoresMouseEvents = true
        panel.makeFirstResponder(nil)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.05
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
                guard let self, event.window === self.panel else { return false }
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

