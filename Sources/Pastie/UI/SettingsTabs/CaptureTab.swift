import SwiftUI

struct CaptureTab: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Text", isOn: $viewModel.captureText)
                Toggle("Images", isOn: $viewModel.captureImages)
                Toggle("Files", isOn: $viewModel.captureFiles)
            } header: {
                Text("What to Capture")
            } footer: {
                SettingHint("Copies marked concealed or transient — what password managers are expected to set — are skipped whatever these say.")
            }

            Section {
                Picker("Keep images up to", selection: $viewModel.maxImageSizeMB) {
                    Text("1 MB").tag(1)
                    Text("5 MB").tag(5)
                    Text("10 MB").tag(10)
                    Text("25 MB").tag(25)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Images")
            } footer: {
                SettingHint("Anything larger is stored as a 400-point-wide thumbnail. The original is not kept.")
            }

            Section {
                Toggle("Keep formatting", isOn: $viewModel.rtfCaptureEnabled)
                StepperRow(title: "Formatting size limit", value: $viewModel.rtfSizeCapMB, range: 1...25, suffix: "MB")
                    .disabled(!viewModel.rtfCaptureEnabled)
            } header: {
                Text("Formatting")
            } footer: {
                SettingHint("Styled text keeps its formatting for ↵ and drops it for ⇧↵. Past the limit, the clip keeps its plain text only.")
            }
        }
    }
}
