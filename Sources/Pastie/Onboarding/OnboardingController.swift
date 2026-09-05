// Sources/Pastie/Onboarding/OnboardingController.swift
import AppKit

/// First-run explanation of why Pastie needs Accessibility permission, shown before macOS's own
/// bare system prompt. Without the explanation the request reads as a clipboard app asking to
/// control your computer, and gets denied.
final class OnboardingController {
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private let accessibility: AccessibilityStatus
    private var window: NSWindow?
    private var recheckObserver: NSObjectProtocol?

    init(accessibility: AccessibilityStatus = SystemAccessibilityStatus()) {
        self.accessibility = accessibility
    }

    var shouldPresent: Bool { !accessibility.isTrusted }

    func presentIfNeeded() {
        guard shouldPresent else { return }
        present()
    }

    func present() {
        let alert = NSAlert()
        alert.messageText = "Pastie needs Accessibility permission"
        alert.informativeText = """
        Pastie pastes by pressing ⌘V for you in whatever app you're using. macOS only lets an app \
        send keystrokes to other apps if you grant it Accessibility permission.

        Without it, Pastie still keeps your clipboard history — it just puts the clip on your \
        clipboard and leaves you to press ⌘V yourself.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.accessibilitySettingsURL)
            observeReturnToApp()
        }
    }

    /// Once the user comes back from System Settings, stop nagging if they granted it.
    private func observeReturnToApp() {
        recheckObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.accessibility.isTrusted else { return }
            if let observer = self.recheckObserver {
                NotificationCenter.default.removeObserver(observer)
                self.recheckObserver = nil
            }
        }
    }
}
