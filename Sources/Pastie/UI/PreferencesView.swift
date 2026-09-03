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
        .frame(width: 480, height: 360)
    }
}
