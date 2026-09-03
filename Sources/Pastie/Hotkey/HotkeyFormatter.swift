import AppKit
import Foundation
import HotKey

enum HotkeyFormatter {
    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += Key(carbonKeyCode: keyCode)?.description ?? "?"
        return result
    }
}
