// Sources/Pastie/Paste/PasteEngine.swift
import AppKit
import ApplicationServices
import CoreGraphics

final class PasteEngine {
    private static let virtualKeyV: CGKeyCode = 9

    /// Writes each clip to the pasteboard and simulates ⌘V, in order (paste-as-list).
    /// Returns false without pasting if Accessibility permission isn't granted —
    /// caller should fall back to "copied to clipboard, paste manually".
    @discardableResult
    func paste(_ clips: [Clip]) -> Bool {
        guard let first = clips.first else { return true }
        writeToPasteboard(first)
        guard AXIsProcessTrusted() else { return false }
        simulatePasteKeystroke()
        Thread.sleep(forTimeInterval: 0.05)
        for clip in clips.dropFirst() {
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
