// Sources/Pastie/UI/ExcludedAppPicker.swift
import AppKit
import UniformTypeIdentifiers

/// Chooses apps to exclude by picking them, rather than asking anyone to type a bundle identifier.
/// Returns the identifiers of what was picked — the only thing the capture filter can match on.
enum ExcludedAppPicker {
    static func pick() -> [String] {
        let panel = NSOpenPanel()
        panel.title = "Apps Pastie Should Ignore"
        panel.message = "Pastie captures nothing while one of these apps is frontmost."
        panel.prompt = "Ignore App"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }
}
