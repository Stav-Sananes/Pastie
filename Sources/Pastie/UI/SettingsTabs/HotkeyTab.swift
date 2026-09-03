import SwiftUI

struct HotkeyTab: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section("Global Hotkey") {
                HotkeyRecorderView(displayText: viewModel.hotkeyDisplay) { keyCode, modifiers in
                    viewModel.updateHotkey(keyCode: keyCode, modifiers: modifiers)
                }
                .frame(height: 28)
                Text("Click the field above and press a key combo. Must include at least one modifier key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
