import AppKit
import LauncherCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var panel: PanelController?
    private(set) var hotKey: HotKey?
    let indexer = Indexer()
    let model = SearchModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist sets LSUIElement; this covers `swift run`, which has no Info.plist.
        NSApp.setActivationPolicy(.accessory)

        indexer.onChange = { [weak self] in self?.model.index = $0 }
        indexer.start()

        let panel = PanelController(content: SearchView(model: model))
        self.panel = panel
        panel.willShow = { [weak self] in
            guard let self else { return }
            indexer.checkIfStale()
            model.query = ""
            model.refresh()
        }
        panel.didHide = { [weak self] in self?.model.query = "" }
        panel.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        panel.composingChanged = { [weak self] in self?.model.isComposing = $0 }
        model.onActivate = { [weak self] in self?.perform($0) }
        hotKey = HotKey { [weak self] in self?.togglePanel() }
        #if DEBUG
        DebugSnapshot.runIfAsked(self)
        #endif
    }

    func togglePanel() {
        if panel?.isShown == true { panel?.hide() } else { showPanel() }
    }

    func showPanel() {
        panel?.show()
        // After the panel is key, so the field can take focus.
        DispatchQueue.main.async { self.model.focusRequest += 1 }
    }

    /// The keys a text field would otherwise swallow. Not called while an input method composes.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags == .command
        switch Int(event.keyCode) {
        case 125: model.move(1); return true        // ↓
        case 126: model.move(-1); return true       // ↑
        case 48: model.acceptGhost(); return true   // ⇥
        case 53:                                    // esc
            if !model.clear() { panel?.hide() }
            return true
        case 36, 76:                                // ↩ and ⌘↩
            model.activateSelection(reveal: command)
            return true
        default:
            break
        }
        guard command, let key = event.charactersIgnoringModifiers else { return false }
        if key == "c" { return model.copyResult() }
        if model.query.isEmpty, let n = Int(key), (1...5).contains(n) { return model.openRecent(n) }
        return false
    }

    private func perform(_ activation: Activation) {
        panel?.hide()
    }
}
