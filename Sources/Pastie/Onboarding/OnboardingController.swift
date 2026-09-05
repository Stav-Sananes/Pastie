// Sources/Pastie/Onboarding/OnboardingController.swift
import AppKit

/// First-run explanation of why Pastie needs Accessibility permission, shown before macOS's own
/// bare system prompt. Without the explanation the request reads as a clipboard app asking to
/// control your computer, and gets denied.
final class OnboardingController {
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private let accessibility: AccessibilityStatus
    private let preferences: PreferencesStore
    private let version: String
    private var recheckObserver: NSObjectProtocol?

    init(
        accessibility: AccessibilityStatus = SystemAccessibilityStatus(),
        preferences: PreferencesStore = PreferencesStore(),
        version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    ) {
        self.accessibility = accessibility
        self.preferences = preferences
        self.version = version
    }

    /// Explain only when the permission is actually missing, and only once per version — an
    /// explanation the user has already dismissed is nagging, not onboarding.
    var shouldPresent: Bool {
        !accessibility.isTrusted && preferences.accessibilityExplainedForVersion != version
    }

    func markExplained() {
        preferences.accessibilityExplainedForVersion = version
    }

    /// Presented off the launch turn: an alert raised from applicationDidFinishLaunching blocks
    /// the run loop before the status item is usable, so the menu bar looks frozen behind it.
    func presentIfNeeded() {
        guard shouldPresent else { return }
        markExplained()
        DispatchQueue.main.async { [weak self] in
            self?.present()
        }
    }

    func present() {
        let alert = NSAlert()
        alert.messageText = "Pastie needs Accessibility permission"
        alert.informativeText = """
        Pastie pastes by pressing ⌘V for you in whatever app you're using. macOS only lets an app \
        send keystrokes to other apps if you grant it Accessibility permission.

        Without it, Pastie still keeps your clipboard history — it just puts the clip on your \
        clipboard and leaves you to press ⌘V yourself.

        Already granted it? Updating Pastie invalidates the permission, because this build is not \
        signed with an Apple Developer ID. Switch Pastie off and back on in the Accessibility list \
        to restore it.
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
