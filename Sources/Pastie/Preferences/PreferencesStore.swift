import AppKit
import Foundation

final class PreferencesStore {
    private let defaults: UserDefaults

    private enum Keys {
        static let excludedBundleIDs = "excludedBundleIDs"
        static let retentionCount = "retentionCount"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let launchAtLogin = "launchAtLogin"
        static let captureText = "captureText"
        static let captureImages = "captureImages"
        static let captureFiles = "captureFiles"
        static let maxImageSizeMB = "maxImageSizeMB"
        static let popupRowCount = "popupRowCount"
        static let rtfCaptureEnabled = "rtfCaptureEnabled"
        static let rtfSizeCapBytes = "rtfSizeCapBytes"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var excludedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.excludedBundleIDs) }
    }

    /// Keep the formatted (RTF) representation of copied text. See ADR 0002.
    var rtfCaptureEnabled: Bool {
        get { defaults.object(forKey: Keys.rtfCaptureEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.rtfCaptureEnabled) }
    }

    /// Rich payloads larger than this are dropped; the clip keeps its plain text.
    var rtfSizeCapBytes: Int {
        get { defaults.object(forKey: Keys.rtfSizeCapBytes) as? Int ?? 1_048_576 }
        set { defaults.set(newValue, forKey: Keys.rtfSizeCapBytes) }
    }

    var retentionCount: Int {
        get { defaults.object(forKey: Keys.retentionCount) as? Int ?? 500 }
        set { defaults.set(newValue, forKey: Keys.retentionCount) }
    }

    var hotkeyKeyCode: UInt32 {
        get { defaults.object(forKey: Keys.hotkeyKeyCode) as? UInt32 ?? 9 } // kVK_ANSI_V
        set { defaults.set(newValue, forKey: Keys.hotkeyKeyCode) }
    }

    var hotkeyModifiers: UInt32 {
        get {
            defaults.object(forKey: Keys.hotkeyModifiers) as? UInt32
                ?? UInt32(NSEvent.ModifierFlags([.option, .command]).rawValue)
        }
        set { defaults.set(newValue, forKey: Keys.hotkeyModifiers) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    var captureText: Bool {
        get { defaults.object(forKey: Keys.captureText) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.captureText) }
    }

    var captureImages: Bool {
        get { defaults.object(forKey: Keys.captureImages) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.captureImages) }
    }

    var captureFiles: Bool {
        get { defaults.object(forKey: Keys.captureFiles) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.captureFiles) }
    }

    var maxImageSizeMB: Int {
        get { defaults.object(forKey: Keys.maxImageSizeMB) as? Int ?? 5 }
        set { defaults.set(newValue, forKey: Keys.maxImageSizeMB) }
    }

    var popupRowCount: Int {
        get { defaults.object(forKey: Keys.popupRowCount) as? Int ?? 8 }
        set { defaults.set(newValue, forKey: Keys.popupRowCount) }
    }
}
