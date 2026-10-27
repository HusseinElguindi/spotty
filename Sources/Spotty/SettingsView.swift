import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Spotty opens apps and does sums. Press ⌘Space.")
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}
