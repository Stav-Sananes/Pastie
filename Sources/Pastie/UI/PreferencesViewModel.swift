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
