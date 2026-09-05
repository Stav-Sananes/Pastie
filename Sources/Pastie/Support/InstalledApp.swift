// Sources/Pastie/Support/InstalledApp.swift
import AppKit

/// An app named by bundle identifier, resolved to something a person can read. The capture filter
/// matches on the identifier, but `com.1password.1password` is not a thing to show someone — so
/// this pairs it with the app's name and icon when that app is installed, and falls back to the
/// identifier when it is not (an excluded app can be uninstalled without the entry becoming junk).
struct InstalledApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let url: URL?

    var id: String { bundleID }
    var isInstalled: Bool { url != nil }

    static func resolve(_ bundleID: String, workspace: NSWorkspace = .shared) -> InstalledApp {
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            return InstalledApp(bundleID: bundleID, name: bundleID, url: nil)
        }
        return InstalledApp(bundleID: bundleID, name: url.deletingPathExtension().lastPathComponent, url: url)
    }

    /// The app's Finder icon, or the generic application icon when it isn't installed.
    func icon(workspace: NSWorkspace = .shared) -> NSImage {
        guard let url else {
            return NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: nil)
                ?? NSImage(size: NSSize(width: 16, height: 16))
        }
        return workspace.icon(forFile: url.path)
    }
}
