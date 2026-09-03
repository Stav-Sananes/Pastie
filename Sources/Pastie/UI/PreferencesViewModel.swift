import Combine
import Foundation

final class PreferencesViewModel: ObservableObject {
    private let store: PreferencesStore
    private let onHotkeyChanged: () -> Void

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
    @Published var captureText: Bool {
        didSet { store.captureText = captureText }
    }
    @Published var captureImages: Bool {
        didSet { store.captureImages = captureImages }
    }
    @Published var captureFiles: Bool {
        didSet { store.captureFiles = captureFiles }
    }
    @Published var maxImageSizeMB: Int {
        didSet { store.maxImageSizeMB = maxImageSizeMB }
    }
    @Published var popupRowCount: Int {
        didSet { store.popupRowCount = popupRowCount }
    }
    @Published var hotkeyDisplay: String

    init(store: PreferencesStore, onHotkeyChanged: @escaping () -> Void = {}) {
        self.store = store
        self.onHotkeyChanged = onHotkeyChanged
        self.retentionCount = store.retentionCount
        self.launchAtLogin = store.launchAtLogin
        self.excludedBundleIDs = Array(store.excludedBundleIDs).sorted()
        self.captureText = store.captureText
        self.captureImages = store.captureImages
        self.captureFiles = store.captureFiles
        self.maxImageSizeMB = store.maxImageSizeMB
        self.popupRowCount = store.popupRowCount
        self.hotkeyDisplay = HotkeyFormatter.displayString(keyCode: store.hotkeyKeyCode, modifiers: store.hotkeyModifiers)
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

    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        store.hotkeyKeyCode = keyCode
        store.hotkeyModifiers = modifiers
        hotkeyDisplay = HotkeyFormatter.displayString(keyCode: keyCode, modifiers: modifiers)
        onHotkeyChanged()
    }
}
