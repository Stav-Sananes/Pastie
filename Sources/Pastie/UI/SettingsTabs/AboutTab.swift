import SwiftUI

/// Who made Pastie, under what licence, and where to go to read the source, report a problem or
/// say thanks. Nothing on this tab changes a setting.
struct AboutTab: View {
    var body: some View {
        SettingsForm {
            Section {
                LabeledContent("Version", value: ProjectLinks.version)
                LabeledContent("Licence", value: "GNU GPL v3")
            } header: {
                Text("Pastie")
            } footer: {
                SettingHint("Free and open source. You may use, study, share and change it; anything built from it must stay under the same licence. Nothing Pastie stores leaves your machine.")
            }

            Section {
                Link(destination: ProjectLinks.sourceRepository) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: ProjectLinks.issues) {
                    Label("Report a problem or suggest a feature", systemImage: "ladybug")
                }
                Link(destination: ProjectLinks.licence) {
                    Label("Read the licence", systemImage: "doc.text")
                }
            } header: {
                Text("Project")
            }

            Section {
                Link(destination: ProjectLinks.buyMeACoffee) {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer")
                }
            } header: {
                Text("Support")
            } footer: {
                SettingHint("Pastie is built in spare time and costs nothing. If it saves you a few minutes a day, a coffee is a kind way to say so.")
            }
        }
    }
}
