import SwiftUI

struct AppearanceTab: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        SettingsForm {
            Section {
                StepperRow(title: "Rows shown", value: $viewModel.popupRowCount, range: 3...20)
            } header: {
                Text("Popup")
            } footer: {
                SettingHint("How tall the popup opens. It scrolls past this; the search field is faster than scrolling.")
            }
        }
    }
}
