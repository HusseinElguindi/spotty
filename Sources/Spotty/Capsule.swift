import AppKit
import SwiftUI

/// The small pill that says what just happened ("Opening Safari", "Copied 1,467.87") in place of
/// the closed panel. It ignores the mouse, pops in, holds 1.4 s and fades.
@MainActor
final class CapsuleController {
    private let panel: NSPanel
    private var generation = 0

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
    }

    /// Shows `text` centred on `top`, the launcher's top edge, on the screen it was on.
    func show(_ text: String, centeredAt x: CGFloat, top: CGFloat) {
        generation += 1
        let current = generation
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let host = NSHostingView(rootView: CapsuleView(text: text, pops: !reduceMotion))
        let size = host.fittingSize
        panel.contentView = host
        panel.setFrame(NSRect(x: (x - size.width / 2).rounded(), y: top - 4 - size.height,
                              width: size.width, height: size.height), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.1, 1)
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13 + 1.4) { [weak self] in
            guard let self, self.generation == current else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.13
                self.panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    if self.generation == current { self.panel.orderOut(nil) }
                }
            })
        }
    }
}

private struct CapsuleView: View {
    let text: String
    let pops: Bool
    @State private var shown = false

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Quiet.ink1)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Quiet.plate, in: .capsule)
            .overlay(Capsule().strokeBorder(Quiet.panelRing, lineWidth: 0.5))
            .scaleEffect(shown || !pops ? 1 : 0.92)
            .onAppear {
                withAnimation(.timingCurve(0.2, 0.9, 0.1, 1, duration: 0.13)) { shown = true }
            }
    }
}
