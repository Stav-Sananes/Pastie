import SwiftUI

struct GeneralTab: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        SettingsForm {
            Section {
                StepperRow(title: "Clips to keep", value: $viewModel.retentionCount, range: 50...5000, step: 50)
                Toggle("Launch Pastie at login", isOn: $viewModel.launchAtLogin)
            } header: {
                Text("History")
            } footer: {
                SettingHint("Saved clips don't count towards the limit and are never dropped. Pastie runs in the menu bar — no Dock icon, no window.")
            }

            Section {
                ExcludedAppsList(viewModel: viewModel)
            } header: {
                Text("Excluded Apps")
            } footer: {
                SettingHint("Pastie captures nothing while one of these apps is frontmost. Use it for anything that copies secrets without marking them concealed.")
            }
        }
    }
}

/// The excluded-app list: pick apps rather than typing bundle identifiers, which is what the
/// capture filter matches on but not something to ask a person to know.
private struct ExcludedAppsList: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.excludedApps.isEmpty {
                VStack(spacing: 4) {
                    Text("No excluded apps")
                        .foregroundStyle(.secondary)
                    Text("Everything you copy is captured.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 96)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.excludedApps) { app in
                            ExcludedAppRow(app: app) {
                                viewModel.removeExcluded(bundleIDs: [app.bundleID])
                            }
                            Divider()
                        }
                    }
                }
                .frame(height: 96)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    viewModel.addExcluded(bundleIDs: ExcludedAppPicker.pick())
                } label: {
                    Label("Add App…", systemImage: "plus")
                }
                .controlSize(.small)

                Spacer()

                if !viewModel.excludedApps.isEmpty {
                    Text("^[\(viewModel.excludedApps.count) app](inflect: true) excluded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }
}

private struct ExcludedAppRow: View {
    let app: InstalledApp
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon())
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name)
                if app.isInstalled {
                    Text(app.bundleID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not installed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Stop excluding \(app.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}
