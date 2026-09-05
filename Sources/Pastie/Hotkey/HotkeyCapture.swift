// Sources/Pastie/Hotkey/HotkeyCapture.swift
import AppKit
import Foundation

enum HotkeyCapture {
    /// A captured key combo must include at least one "real" modifier — a bare letter
    /// shouldn't silently rebind the global hotkey while the user is just typing, and
    /// capsLock/function are device state, not a deliberate modifier choice.
    static func isValidBinding(modifiers: NSEvent.ModifierFlags) -> Bool {
        !modifiers.intersection([.command, .option, .control, .shift]).isEmpty
    }
}
