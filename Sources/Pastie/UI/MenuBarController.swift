// Sources/Pastie/UI/MenuBarController.swift
import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popupController: PopupWindowController
    private let clipStore: ClipStore
    private let preferences: PreferencesStore
    private let onOpenPreferences: () -> Void
    private let openPastieItem = NSMenuItem()

    init(popupController: PopupWindowController, clipStore: ClipStore, preferences: PreferencesStore, onOpenPreferences: @escaping () -> Void) {
        self.popupController = popupController
        self.clipStore = clipStore
        self.preferences = preferences
        self.onOpenPreferences = onOpenPreferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pastie")
        }

        openPastieItem.title = "Open Pastie"
        openPastieItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        openPastieItem.action = #selector(openPopup)
        openPastieItem.target = self

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        preferencesItem.target = self

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        clearItem.target = self

        let quitItem = NSMenuItem(title: "Quit Pastie", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(openPastieItem)
        menu.addItem(.separator())
        menu.addItem(preferencesItem)
        menu.addItem(clearItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
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

extension MenuBarController: NSMenuDelegate {
    // Refreshes the "Open Pastie" title with the live hotkey binding each time the
    // menu opens, so a remap in Settings shows up without rebuilding the whole menu.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let hotkey = HotkeyFormatter.displayString(keyCode: preferences.hotkeyKeyCode, modifiers: preferences.hotkeyModifiers)
        openPastieItem.title = "Open Pastie    \(hotkey)"
    }
}
