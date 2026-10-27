import SwiftUI

@main
struct SpottyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Spotty", systemImage: "magnifyingglass") {
            MenuContent(delegate: delegate)
        }
    }
}

private struct MenuContent: View {
    let delegate: AppDelegate

    var body: some View {
        Button("Open Spotty") { delegate.showPanel() }
        if delegate.hotKey?.isRegistered == false {
            Text("⌘Space is taken by another app")
        }
        Divider()
        Button("Settings…") { delegate.showSettings() }
            .keyboardShortcut(",")
        Button("Quit Spotty") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
