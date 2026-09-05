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
    ///
    /// `plain` drops the rich payload, which is what ⇧↵ in the popup asks for.
    @discardableResult
    func paste(_ clips: [Clip], plain: Bool = false, beforeEachWrite: (() -> Void)? = nil) -> Bool {
        guard let first = clips.first else { return true }
        beforeEachWrite?()
        writeToPasteboard(first, plain: plain, pasteboard: .general)
        guard AXIsProcessTrusted() else { return false }
        simulatePasteKeystroke()
        Thread.sleep(forTimeInterval: 0.05)
        for clip in clips.dropFirst() {
            beforeEachWrite?()
            writeToPasteboard(clip, plain: plain, pasteboard: .general)
            simulatePasteKeystroke()
            Thread.sleep(forTimeInterval: 0.05)
        }
        return true
    }

    /// Internal rather than private so tests can drive it against a named pasteboard instead of
    /// the system one; the keystroke half of paste() has no testable seam.
    func writeToPasteboard(_ clip: Clip, plain: Bool, pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch clip.type {
        case .text:
            guard let text = clip.textContent else { return }
            if !plain, let rtf = clip.rtfData {
                // Declare RTF first: the destination takes the richest type it understands, and
                // an app that only reads plain text still finds the string below.
                pasteboard.declareTypes([.rtf, .string], owner: nil)
                pasteboard.setData(rtf, forType: .rtf)
            }
            pasteboard.setString(text, forType: .string)
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
