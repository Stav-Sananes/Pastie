import AppKit
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
    @Published var rtfCaptureEnabled: Bool {
        didSet { store.rtfCaptureEnabled = rtfCaptureEnabled }
    }
    /// Shown in megabytes, stored in bytes. Clamped 1–25MB: 0 would quietly turn rich payloads
    /// off through a control that doesn't say so, and nothing sensible needs more than 25.
    @Published var rtfSizeCapMB: Int {
        didSet {
            let clamped = min(max(rtfSizeCapMB, 1), 25)
            store.rtfSizeCapBytes = clamped * 1_048_576
        }
    }
    @Published var slotHotkeyModifierChoice: SlotModifierChoice {
        didSet {
            store.slotHotkeyModifiers = UInt32(slotHotkeyModifierChoice.flags.rawValue)
            onHotkeyChanged()
        }
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
        self.rtfCaptureEnabled = store.rtfCaptureEnabled
        self.rtfSizeCapMB = store.rtfSizeCapBytes / 1_048_576
        let storedFlags = NSEvent.ModifierFlags(rawValue: UInt(store.slotHotkeyModifiers))
        self.slotHotkeyModifierChoice = SlotModifierChoice.allCases.first { $0.flags == storedFlags } ?? .optionCommand
        self.hotkeyDisplay = HotkeyFormatter.displayString(keyCode: store.hotkeyKeyCode, modifiers: store.hotkeyModifiers)
    }

    /// The excluded apps as something a list can render: name and icon where the app is
    /// installed, the identifier itself where it is not.
    var excludedApps: [InstalledApp] {
        excludedBundleIDs.map { InstalledApp.resolve($0) }
    }

    /// Adds everything the picker returned. Blanks and identifiers already on the list are
    /// ignored, so picking the same app twice is a no-op rather than a duplicate row.
    func addExcluded(bundleIDs: [String]) {
        for bundleID in bundleIDs {
            let trimmed = bundleID.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !excludedBundleIDs.contains(trimmed) else { continue }
            excludedBundleIDs.append(trimmed)
        }
        excludedBundleIDs.sort()
        store.excludedBundleIDs = Set(excludedBundleIDs)
    }

    func removeExcluded(at offsets: IndexSet) {
        removeExcluded(bundleIDs: offsets.map { excludedBundleIDs[$0] })
    }

    /// Removes by identifier rather than by index: the list hands back a selection, and an index
    /// computed against a differently sorted array would delete the wrong row.
    func removeExcluded(bundleIDs: [String]) {
        let doomed = Set(bundleIDs)
        guard !doomed.isEmpty else { return }
        excludedBundleIDs.removeAll { doomed.contains($0) }
        store.excludedBundleIDs = Set(excludedBundleIDs)
    }

    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        store.hotkeyKeyCode = keyCode
        store.hotkeyModifiers = modifiers
        hotkeyDisplay = HotkeyFormatter.displayString(keyCode: keyCode, modifiers: modifiers)
        onHotkeyChanged()
    }
}

/// The modifier combination the global quick-paste hotkeys use with digits 1–9. Only the
/// modifier is configurable — the digits are the slot numbers.
enum SlotModifierChoice: String, CaseIterable, Identifiable {
    case optionCommand, controlCommand, shiftCommand
    var id: String { rawValue }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .optionCommand: return [.option, .command]
        case .controlCommand: return [.control, .command]
        case .shiftCommand: return [.shift, .command]
        }
    }
}
