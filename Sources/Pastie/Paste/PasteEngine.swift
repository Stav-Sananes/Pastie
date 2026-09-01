// Sources/Pastie/Paste/PasteEngine.swift
import AppKit
import ApplicationServices
import CoreGraphics

final class PasteEngine {
    private static let virtualKeyV: CGKeyCode = 9

    /// Writes each clip to the pasteboard and simulates ⌘V, in order (paste-as-list).
    /// Returns false without pasting if Accessibility permission isn't granted —
    /// caller should fall back to "copied to clipboard, paste manually".
    ///
    /// `beforeEachWrite` is invoked immediately before each pasteboard write (once per clip) so
    /// a caller holding a ClipboardMonitor can tell it to ignore the resulting pasteboard change
    /// (see ClipboardMonitor.ignoreNextChange) and avoid re-capturing our own paste as a new clip.
    @discardableResult
    func paste(_ clips: [Clip], beforeEachWrite: (() -> Void)? = nil) -> Bool {
        guard let first = clips.first else { return true }
        beforeEachWrite?()
        writeToPasteboard(first)
        guard AXIsProcessTrusted() else { return false }
        simulatePasteKeystroke()
        Thread.sleep(forTimeInterval: 0.05)
        for clip in clips.dropFirst() {
            beforeEachWrite?()
            writeToPasteboard(clip)
            simulatePasteKeystroke()
            Thread.sleep(forTimeInterval: 0.05)
        }
        return true
    }

    private func writeToPasteboard(_ clip: Clip) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch clip.type {
        case .text:
            if let text = clip.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let data = clip.imageData, let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .file:
            if let path = clip.filePath {
                pasteboard.writeObjects([NSURL(fileURLWithPath: path)])
            }
        }
    }

    private func simulatePasteKeystroke() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.virtualKeyV, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.virtualKeyV, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
