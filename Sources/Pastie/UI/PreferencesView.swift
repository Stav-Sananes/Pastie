import SwiftUI

struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Stepper("Retention: \(viewModel.retentionCount) items", value: $viewModel.retentionCount, in: 50...5000, step: 50)
            Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
            Section("Excluded Apps") {
                List {
                    ForEach(viewModel.excludedBundleIDs, id: \.self) { id in
                        Text(id)
                    }
                    .onDelete(perform: viewModel.removeExcluded)
                }
                HStack {
                    TextField("Bundle ID (e.g. com.1password.1password)", text: $viewModel.newBundleID)
                    Button("Add") { viewModel.addExcluded() }
                }
            }
        }
        .padding()
        .frame(width: 380, height: 420)
    }
}
