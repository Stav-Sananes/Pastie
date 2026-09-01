import AppKit
import Foundation

enum HotkeyFormatter {
    private static let keyLabels: [UInt32: String] = [
        0: "A", 8: "C", 9: "V", 3: "F", 45: "N", 1: "S", 17: "T"
    ]

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += keyLabels[keyCode] ?? "?"
        return result
    }
}
