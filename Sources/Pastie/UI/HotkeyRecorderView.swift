// Sources/Pastie/UI/HotkeyRecorderView.swift
import AppKit
import HotKey
import SwiftUI

/// Captures the next key-down as a global hotkey binding. Click to start recording;
/// press a combo (must include a modifier — see HotkeyCapture); Escape cancels.
final class HotkeyRecorderNSView: NSView {
    var isRecording = false {
        didSet { needsDisplay = true }
    }
    var onCapture: ((UInt32, UInt32) -> Void)?
    private let label = NSTextField(labelWithString: "")

    var displayText: String = "" {
        didSet {
            guard !isRecording else { return }
            label.stringValue = displayText
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.frame = bounds
        label.autoresizingMask = [.width, .height]
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var acceptsFirstResponder: Bool { true }

    override var wantsUpdateLayer: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
        label.stringValue = "Press a key combo…"
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 { // Escape cancels
            isRecording = false
            label.stringValue = displayText
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard HotkeyCapture.isValidBinding(modifiers: modifiers), Key(carbonKeyCode: UInt32(event.keyCode)) != nil else { return }
        isRecording = false
        onCapture?(UInt32(event.keyCode), UInt32(modifiers.rawValue))
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        label.stringValue = displayText
        return super.resignFirstResponder()
    }

    override func updateLayer() {
        layer?.backgroundColor = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
            : NSColor.clear.cgColor
    }
}

struct HotkeyRecorderView: NSViewRepresentable {
    let displayText: String
    let onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView(frame: .zero)
        view.displayText = displayText
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.displayText = displayText
        nsView.onCapture = onCapture
    }
}
