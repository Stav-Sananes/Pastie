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
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var excludedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.excludedBundleIDs) }
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
}
