// Sources/Pastie/UI/MenuBarController.swift
import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popupController: PopupWindowController
    private let clipStore: ClipStore
    private let onOpenPreferences: () -> Void

    init(popupController: PopupWindowController, clipStore: ClipStore, onOpenPreferences: @escaping () -> Void) {
        self.popupController = popupController
        self.clipStore = clipStore
        self.onOpenPreferences = onOpenPreferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pastie")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Pastie", action: #selector(openPopup), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Clear History", action: #selector(clearHistory), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pastie", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func openPopup() {
        popupController.show()
    }

    @objc private func openPreferences() {
        onOpenPreferences()
    }

    @objc private func clearHistory() {
        try? clipStore.clearAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
