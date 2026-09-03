import SwiftUI

struct AppearanceTab: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Stepper("Rows shown in popup: \(viewModel.popupRowCount)", value: $viewModel.popupRowCount, in: 3...20)
        }
        .padding()
    }
}
