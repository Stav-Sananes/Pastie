import SwiftUI

struct CaptureTab: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Capture text", isOn: $viewModel.captureText)
                Toggle("Capture images", isOn: $viewModel.captureImages)
                Toggle("Capture files", isOn: $viewModel.captureFiles)
            }
            Section("Image Size") {
                Picker("Max image size to keep", selection: $viewModel.maxImageSizeMB) {
                    Text("1 MB").tag(1)
                    Text("5 MB").tag(5)
                    Text("10 MB").tag(10)
                    Text("25 MB").tag(25)
                }
                .pickerStyle(.segmented)
            }
            Section("Formatting") {
                Toggle("Keep formatting (RTF)", isOn: $viewModel.rtfCaptureEnabled)
                Stepper("Maximum formatting size: \(viewModel.rtfSizeCapMB) MB",
                        value: $viewModel.rtfSizeCapMB, in: 1...25)
                    .disabled(!viewModel.rtfCaptureEnabled)
                Text("Formatted text larger than this is stored as plain text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
