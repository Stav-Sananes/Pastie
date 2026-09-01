import Combine
import Foundation

final class PreferencesViewModel: ObservableObject {
    private let store: PreferencesStore

    @Published var retentionCount: Int {
        didSet { store.retentionCount = retentionCount }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            store.launchAtLogin = launchAtLogin
            LaunchAtLogin.set(launchAtLogin)
        }
    }
    @Published var excludedBundleIDs: [String]
    @Published var newBundleID: String = ""

    init(store: PreferencesStore) {
        self.store = store
        self.retentionCount = store.retentionCount
        self.launchAtLogin = store.launchAtLogin
        self.excludedBundleIDs = Array(store.excludedBundleIDs).sorted()
    }

    func addExcluded() {
        let trimmed = newBundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !excludedBundleIDs.contains(trimmed) else {
            newBundleID = ""
            return
        }
        excludedBundleIDs.append(trimmed)
        excludedBundleIDs.sort()
        store.excludedBundleIDs = Set(excludedBundleIDs)
        newBundleID = ""
    }

    func removeExcluded(at offsets: IndexSet) {
        for index in offsets {
            store.excludedBundleIDs.remove(excludedBundleIDs[index])
        }
        for index in offsets.sorted(by: >) {
            excludedBundleIDs.remove(at: index)
        }
    }
}
