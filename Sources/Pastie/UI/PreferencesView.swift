import SwiftUI

// Each tab is a standalone file under SettingsTabs/ taking the shared viewModel.
// Adding a future tab (e.g. "Groups", "Actions") means: one new file + one new
// case here — never gate anything elsewhere on "there are 4 tabs".
struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }
            HotkeyTab(viewModel: viewModel)
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
            CaptureTab(viewModel: viewModel)
                .tabItem { Label("Capture", systemImage: "tray.and.arrow.down") }
            AppearanceTab(viewModel: viewModel)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        // One size for every tab: a Settings window that resizes as you switch tabs reads as a
        // glitch. The tallest tab (Hotkey, with its key reference) sets the height.
        .frame(width: 540, height: 600)
    }
}

/// Every tab is a grouped Form — the shape macOS Settings itself uses, which is what gives the
/// aligned label column and the section chrome a bare `Form` on macOS 13 does not.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// A caption under a control. Settings that need a sentence of explanation get one here rather
/// than in a tooltip nobody hovers.
struct SettingHint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A number with its stepper, laid out as one control against a label. `Stepper`'s own label
/// leaves the value stranded beside the title with the buttons an inch away, which reads as two
/// unrelated things.
struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var suffix: String = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(suffix.isEmpty ? "\(value)" : "\(value) \(suffix)")
                    .monospacedDigit()
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}
