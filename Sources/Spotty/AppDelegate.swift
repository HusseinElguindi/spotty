import AppKit
import LauncherCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var panel: PanelController?
    private(set) var hotKey: HotKey?
    let indexer = Indexer()
    let model = SearchModel()
    private let usageFile = UsageFile()
    private let capsule = CapsuleController()
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist sets LSUIElement; this covers `swift run`, which has no Info.plist.
        NSApp.setActivationPolicy(.accessory)
        model.usage = usageFile.load()
        noteActivations()

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

    func applicationWillTerminate(_ notification: Notification) {
        usageFile.saveNow(model.usage)
    }

    /// Settings' "Reset learned ranking".
    func resetLearning() {
        model.usage = UsageStore()
        usageFile.saveNow(model.usage)
        model.refresh()
    }

    private func perform(_ activation: Activation) {
        guard let panel else { return }
        let frame = panel.panel.frame
        let say = { [capsule] (text: String) in capsule.show(text, centeredAt: frame.midX, top: frame.maxY) }
        switch activation {
        case .copy(let display, let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)  // "1467.87", never "1,467.87"
            panel.hide()
            say("Copied \(display)")
        case .launch(let app, _, _, reveal: true):
            panel.hide()
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
        case .launch(let app, let query, let picked, reveal: false):
            let typed = query.trimmingCharacters(in: .whitespaces)
            // An empty query (a Recent row) only updates frecency and recents, never a pick.
            let taught = model.usage.recordLaunch(of: app.id, query: QueryKeys(typed), at: .now)
            usageFile.scheduleSave(model.usage)
            panel.hide()
            say(taught && picked > 0 ? "“\(typed)” now opens \(app.name) first." : "Opening \(app.name)")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, error in
                guard error != nil else { return }
                // Moved or deleted since the last scan.
                Task { @MainActor in self.indexer.rescan() }
            }
        }
    }

    /// Apps brought to the front some other way (Dock, ⌘Tab) count as recent too.
    private func noteActivations() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let id, id != Bundle.main.bundleIdentifier else { return }
                self.model.usage.noteUse(of: id, at: .now)
                self.usageFile.scheduleSave(self.model.usage)
            }
        }
    }
}
