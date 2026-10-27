#if DEBUG
import AppKit

/// Development aid: `SPOTTY_SNAPSHOT='query|/tmp/out.png'` opens the panel, types the query,
/// saves the panel as a PNG and quits. Several shots: separate them with `;`. A query ending in
/// `⏎` presses Return and saves the capsule instead.
@MainActor
enum DebugSnapshot {
    static func runIfAsked(_ app: AppDelegate) {
        let env = ProcessInfo.processInfo.environment
        guard let spec = env["SPOTTY_SNAPSHOT"] else { return }
        // `SPOTTY_APPEARANCE=light` or `dark` overrides the system appearance for the shots.
        if let look = env["SPOTTY_APPEARANCE"] { NSApp.appearance = NSAppearance(named: look == "light" ? .aqua : .darkAqua) }
        let shots = spec.split(separator: ";").map { $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init) }
        // Give the first scan time to finish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { take(shots[...], app) }
    }

    private static func take(_ shots: ArraySlice<[String]>, _ app: AppDelegate) {
        guard let shot = shots.first, shot.count == 2, let panel = app.panel else { NSApp.terminate(nil); return }
        // `settings|out.png` saves the settings window instead.
        if shot[0] == "settings" {
            app.showSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let window = NSApp.windows.first(where: { $0.title == "Spotty Settings" }),
                   let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: shot[1]))
                    print("snapshot \(shot[1]) settings frame=\(window.frame)")
                    window.close()
                }
                take(shots.dropFirst(), app)
            }
            return
        }
        // Every shot closes and reopens the panel, as a real ⌘Space would, unless its query
        // starts with `=`, which keeps the panel as it is.
        let keep = shot[0].hasPrefix("=")
        if panel.isShown && !keep {
            panel.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { take(shots, app) }
            return
        }
        if !panel.isShown { app.showPanel() }
        let query = keep ? String(shot[0].dropFirst()) : shot[0]
        let returns = query.hasSuffix("⏎")
        app.model.query = returns ? String(query.dropLast()) : query
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if returns { app.model.activateSelection() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let window = returns ? NSApp.windows.first { $0.ignoresMouseEvents && $0.isVisible } : panel.panel
            if let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: shot[1]))
            }
            print("snapshot \(shot[1]) selection=\(app.model.selection) key=\(panel.panel.isKeyWindow) frame=\(panel.panel.frame) active=\(NSApp.isActive)")
            take(shots.dropFirst(), app)
        }
    }
}
#endif
