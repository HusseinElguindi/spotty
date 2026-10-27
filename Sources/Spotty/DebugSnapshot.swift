#if DEBUG
import AppKit

/// Development aid: `SPOTTY_SNAPSHOT='query|/tmp/out.png'` opens the panel, types the query,
/// saves the panel as a PNG and quits. Several shots: separate them with `;`.
@MainActor
enum DebugSnapshot {
    static func runIfAsked(_ app: AppDelegate) {
        guard let spec = ProcessInfo.processInfo.environment["SPOTTY_SNAPSHOT"] else { return }
        let shots = spec.split(separator: ";").map { $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init) }
        // Give the first scan time to finish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { take(shots[...], app) }
    }

    private static func take(_ shots: ArraySlice<[String]>, _ app: AppDelegate) {
        guard let shot = shots.first, shot.count == 2, let panel = app.panel else { NSApp.terminate(nil); return }
        if !panel.isShown { app.showPanel() }
        app.model.query = shot[0]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let view = panel.panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: shot[1]))
            }
            print("snapshot \(shot[1]) key=\(panel.panel.isKeyWindow) frame=\(panel.panel.frame) active=\(NSApp.isActive)")
            take(shots.dropFirst(), app)
        }
    }
}
#endif
