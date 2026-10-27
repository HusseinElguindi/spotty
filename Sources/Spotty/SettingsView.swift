import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let delegate: AppDelegate
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in setOpenAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Shortcut") {
                    Text(delegate.hotKey?.isRegistered == false ? "⌘Space is taken by another app" : "⌘Space")
                }
                Text("Turn off Spotlight's own ⌘Space in System Settings › Keyboard › Keyboard Shortcuts › Spotlight.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Reset learned ranking…") { confirmingReset = true }
                Text("Forgets which app each search opens first and how often you open each app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // A grouped form scrolls and has no height of its own; without one the window is just a title bar.
        .frame(width: 420, height: 270)
        .confirmationDialog("Reset learned ranking?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { delegate.resetLearning() }
        } message: {
            Text("Searches go back to their default order.")
        }
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
