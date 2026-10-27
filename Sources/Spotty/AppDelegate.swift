import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var panel: PanelController?
    private(set) var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist sets LSUIElement; this covers `swift run`, which has no Info.plist.
        NSApp.setActivationPolicy(.accessory)

        let panel = PanelController(content: ShellView())
        self.panel = panel
        hotKey = HotKey { [weak panel] in panel?.toggle() }
        panel.keyHandler = { [weak panel] event in
            guard event.keyCode == 53 else { return false }  // Esc
            panel?.hide()
            return true
        }
    }
}

/// Stand-in content until the search view exists.
private struct ShellView: View {
    @State private var text = ""

    var body: some View {
        TextField("Open an app or calculate", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Quiet.ink1)
            .frame(height: 50)
            .padding(.horizontal, 16)
            .frame(width: 560)
            .background(Quiet.panel, in: .rect(cornerRadius: 16))
    }
}
