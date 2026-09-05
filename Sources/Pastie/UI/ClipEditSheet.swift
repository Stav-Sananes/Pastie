// Sources/Pastie/UI/ClipEditSheet.swift
import AppKit

/// Edit-before-paste. The sheet hands back edited text; the caller pastes it. The stored Clip is
/// never modified — History is a record of what was actually copied.
enum ClipEditSheet {
    static func present(text: String, in window: NSWindow, completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Edit Before Pasting"
        alert.informativeText = "Changes apply to this paste only. The saved clip is unchanged."
        alert.addButton(withTitle: "Paste")
        alert.addButton(withTitle: "Cancel")

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        textView.string = text
        textView.isEditable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll

        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn ? textView.string : nil)
        }
    }
}
