// Sources/Pastie/AppDelegate.swift
import AppKit
import GRDB
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clipStore: ClipStore!
    private var preferences: PreferencesStore!
    private var monitor: ClipboardMonitor!
    private var hotkeyManager: HotkeyManager!
    private var menuBarController: MenuBarController!
    private var popupController: PopupWindowController!
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences = PreferencesStore()

        let dbQueue: DatabaseQueue
        do {
            dbQueue = try DatabaseQueue(path: Self.databasePath())
            clipStore = try ClipStore(dbQueue: dbQueue, retentionCount: preferences.retentionCount)
        } catch {
            NSLog("Pastie: fatal storage init error: \(error)")
            NSApp.terminate(nil)
            return
        }

        popupController = PopupWindowController(store: clipStore, pasteEngine: PasteEngine())

        menuBarController = MenuBarController(
            popupController: popupController,
            clipStore: clipStore,
            onOpenPreferences: { [weak self] in self?.openPreferences() }
        )

        monitor = ClipboardMonitor(store: clipStore, preferences: preferences)
        monitor.start()

        hotkeyManager = HotkeyManager(preferences: preferences) { [weak self] in
            self?.popupController.toggle()
        }
        hotkeyManager.registerFromPreferences()

        requestAccessibilityIfNeeded()
    }

    private func openPreferences() {
        if preferencesWindow == nil {
            let viewModel = PreferencesViewModel(store: preferences)
            let hosting = NSHostingController(rootView: PreferencesView(viewModel: viewModel))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Pastie Preferences"
            window.styleMask = [.titled, .closable]
            preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func databasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Pastie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pastie.sqlite").path
    }
}
