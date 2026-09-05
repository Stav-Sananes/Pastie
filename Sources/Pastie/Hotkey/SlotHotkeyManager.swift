// Sources/Pastie/Hotkey/SlotHotkeyManager.swift
import AppKit
import HotKey

/// Registers a global hotkey per *bound* quick-paste slot. Unbound slots register nothing, so
/// Pastie never holds a system-wide combination it has no use for.
final class SlotHotkeyManager {
    /// Carbon virtual key codes for the digit row. Not sequential — copied, not computed.
    private static let digitKeyCodes: [Int: UInt32] = [
        1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25
    ]

    private let store: ClipStore
    private let preferences: PreferencesStore
    private let onPaste: (Clip) -> Void
    private var hotKeys: [HotKey] = []

    init(store: ClipStore, preferences: PreferencesStore, onPaste: @escaping (Clip) -> Void) {
        self.store = store
        self.preferences = preferences
        self.onPaste = onPaste
    }

    /// Drops every current registration and re-registers one hotkey per bound slot. Safe to call
    /// repeatedly — the popup calls it whenever a binding may have changed.
    func registerBoundSlots() {
        unregisterAll()
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(preferences.slotHotkeyModifiers))
        for slot in ClipStore.slotRange {
            // `try?` on a throwing Optional-returning call flattens to a single Optional in
            // Swift 5, so this is one `!= nil` check, not two.
            guard (try? store.clipForSlot(slot)) != nil else { continue }
            guard let code = Self.digitKeyCodes[slot], let key = Key(carbonKeyCode: code) else { continue }
            let hotKey = HotKey(key: key, modifiers: modifiers)
            hotKey.keyDownHandler = { [weak self] in
                guard let self else { return }
                // Re-read on press: the clip behind a slot can change between registration and use.
                guard let clip = try? self.store.clipForSlot(slot) else {
                    NSSound.beep()   // the slot's clip was deleted since it was bound
                    return
                }
                self.onPaste(clip)
            }
            hotKeys.append(hotKey)
        }
    }

    func unregisterAll() {
        hotKeys.removeAll()
    }
}
