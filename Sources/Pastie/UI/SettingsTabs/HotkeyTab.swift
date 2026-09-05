import SwiftUI

struct HotkeyTab: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        SettingsForm {
            Section {
                LabeledContent("Hotkey") {
                    HotkeyRecorderView(displayText: viewModel.hotkeyDisplay) { keyCode, modifiers in
                        viewModel.updateHotkey(keyCode: keyCode, modifiers: modifiers)
                    }
                    .frame(width: 132, height: 24)
                }
            } header: {
                Text("Open Pastie")
            } footer: {
                SettingHint("Click the field and press the combination you want. It must include at least one modifier. Esc cancels.")
            }

            Section {
                Picker("Modifier", selection: $viewModel.slotHotkeyModifierChoice) {
                    Text("⌥⌘").tag(SlotModifierChoice.optionCommand)
                    Text("⌃⌘").tag(SlotModifierChoice.controlCommand)
                    Text("⇧⌘").tag(SlotModifierChoice.shiftCommand)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Quick-Paste Slots")
            } footer: {
                SettingHint("Press this with 1–9 from any app to paste the clip in that slot, without opening Pastie. Assign a slot by right-clicking a Saved clip.")
            }

            Section("Inside the Popup") {
                KeyRow("↵", "Paste the selected clip")
                KeyRow("⇧↵", "Paste it without formatting")
                KeyRow("⌘1–⌘9", "Paste the Nth visible row")
                KeyRow("⌘T", "Transform before pasting")
                KeyRow("⌘E", "Edit before pasting")
                KeyRow("Esc", "Close the popup")
            }
        }
    }
}

/// A fixed reference row: the popup's keys are otherwise only discoverable by reading the hint
/// line inside the popup itself.
private struct KeyRow: View {
    let keys: String
    let meaning: String

    init(_ keys: String, _ meaning: String) {
        self.keys = keys
        self.meaning = meaning
    }

    var body: some View {
        LabeledContent {
            Text(meaning)
                .foregroundStyle(.secondary)
        } label: {
            Text(keys)
                .font(.system(.body, design: .rounded).monospacedDigit())
        }
    }
}
