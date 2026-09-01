import AppKit
import HotKey

final class HotkeyManager {
    private var hotKey: HotKey?
    private let preferences: PreferencesStore
    private let onTrigger: () -> Void

    init(preferences: PreferencesStore, onTrigger: @escaping () -> Void) {
        self.preferences = preferences
        self.onTrigger = onTrigger
    }

    func registerFromPreferences() {
        guard let key = Key(carbonKeyCode: preferences.hotkeyKeyCode) else {
            NSLog("HotkeyManager: unrecognized key code \(preferences.hotkeyKeyCode)")
            return
        }
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(preferences.hotkeyModifiers))
        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            self?.onTrigger()
        }
    }

    func unregister() {
        hotKey = nil
    }
}
