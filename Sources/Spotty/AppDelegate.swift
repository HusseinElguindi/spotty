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
    private var workspaceObservers: [NSObjectProtocol] = []
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist sets LSUIElement; this covers `swift run`, which has no Info.plist.
        NSApp.setActivationPolicy(.accessory)
        model.usage = usageFile.load()
        noteActivations()

        indexer.onChange = { [weak self] index in
            guard let self else { return }
            let first = model.index.scan.apps.isEmpty
            model.index = index
            if first { panel?.prewarm() }
        }
        indexer.start()

        let panel = PanelController(content: SearchView(model: model))
        self.panel = panel
        panel.willShow = { [weak self] in
            guard let self else { return }
            indexer.checkIfStale()
            model.query = ""
            model.refresh()
            model.notePointer()
        }
        panel.didHide = { [weak self] in self?.model.query = "" }
        panel.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        panel.composingChanged = { [weak self] in self?.model.isComposing = $0 }
        model.onActivate = { [weak self] in self?.perform($0) }
        model.onContentChange = { [weak panel] in panel?.contentChanged() }
        hotKey = HotKey { [weak self] in self?.togglePanel() }
        #if DEBUG
        DebugSnapshot.runIfAsked(self)
        DebugBench.runIfAsked(self)
        DebugIdle.start()
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
        usageFile.flush()
    }

    /// SwiftUI's `Settings` scene and `openSettings` do nothing from a `MenuBarExtra` in an app with
    /// no Dock icon, so Spotty keeps its own settings window.
    func showSettings() {
        let window = settingsWindow ?? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(delegate: self)))
            window.title = "Spotty Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
            return window
        }()
        // An ordinary window, unlike the panel, so it should come to the front. macOS may decline
        // the activation, so order the window in front regardless.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
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
        case .launch(let app, _, reveal: true):
            panel.hide()
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
        case .launch(let app, let query, reveal: false):
            // An empty query (a Recent row) only updates frecency and recents, never a pick.
            model.usage.recordLaunch(of: app.id, query: QueryKeys(query), at: .now)
            usageFile.changed(model.usage, .soon)  // carries a learned pick
            // Nothing is shown after opening an app: the app itself is the confirmation.
            panel.hide()
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
        let center = NSWorkspace.shared.notificationCenter
        // Write anything pending before the Mac sleeps, logs out or switches user.
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.willPowerOffNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [usageFile] _ in
                usageFile.flush()
            })
        }
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                debugNote("activation \(id ?? "?")")
                guard let self, let id, id != Bundle.main.bundleIdentifier else { return }
                self.model.usage.noteUse(of: id, at: .now)
                self.usageFile.changed(self.model.usage, .eventually)  // Recent only
            }
        })
    }
}
