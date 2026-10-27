import AppKit
import LauncherCore
import SwiftUI

/// The guide lines shown while the panel is dragged: the screen's centre line and the line the
/// standard placement's top edge sits on. Faint and dashed, or solid indigo once the panel sticks
/// to one. A click-through window over the whole screen, just below the panel.
@MainActor
final class PanelGuides {
    private let window: NSPanel
    private let view = GuidesView()

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: true)
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = view
    }

    /// Shows the guides for `visible`, the visible area of `screen`, just below `panel`.
    func show(on screen: NSScreen, visible: NSRect, width: CGFloat, tallest: CGFloat, below panel: NSWindow) {
        window.setFrame(screen.frame, display: false)
        let standard = PanelPlacement.standard.resolve(in: visible, width: width, tallest: tallest)
        // In the view's coordinates, which start at the screen's bottom-left corner.
        let origin = screen.frame.origin
        view.visible = visible.offsetBy(dx: -origin.x, dy: -origin.y)
        view.centerX = standard.midX - origin.x
        view.standardTop = standard.top - origin.y
        view.snapped = []
        view.needsDisplay = true
        window.order(.below, relativeTo: panel.windowNumber)
    }

    func update(snapped: PanelPlacement.Guides) {
        guard snapped != view.snapped else { return }
        view.snapped = snapped
        view.needsDisplay = true
    }

    func hide() { window.orderOut(nil) }
}

private final class GuidesView: NSView {
    var visible = NSRect.zero
    var centerX: CGFloat = 0
    var standardTop: CGFloat = 0
    var snapped: PanelPlacement.Guides = []

    override func draw(_ dirtyRect: NSRect) {
        // Half-point offsets keep the 1 pt lines on whole pixels at 1x.
        line(from: NSPoint(x: centerX + 0.5, y: visible.minY), to: NSPoint(x: centerX + 0.5, y: visible.maxY),
             snapped: snapped.contains(.centerX))
        line(from: NSPoint(x: visible.minX, y: standardTop - 0.5), to: NSPoint(x: visible.maxX, y: standardTop - 0.5),
             snapped: snapped.contains(.standardTop))
    }

    private func line(from start: NSPoint, to end: NSPoint, snapped: Bool) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 1
        if snapped {
            NSColor(Quiet.indigo).setStroke()
        } else {
            NSColor(Quiet.ink4).withAlphaComponent(0.5).setStroke()
            path.setLineDash([4, 4], count: 2, phase: 0)
        }
        path.stroke()
    }
}
