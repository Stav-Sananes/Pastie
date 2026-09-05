// Tests/PastieTests/OnboardingControllerTests.swift
import XCTest
@testable import Pastie

private struct StubAccessibility: AccessibilityStatus {
    let isTrusted: Bool
}

final class OnboardingControllerTests: XCTestCase {
    private func makePreferences() -> PreferencesStore {
        PreferencesStore(defaults: UserDefaults(suiteName: "PastieTests.onboarding.\(UUID().uuidString)")!)
    }

    func testPresentsWhenPermissionIsMissing() {
        let controller = OnboardingController(accessibility: StubAccessibility(isTrusted: false), preferences: makePreferences(), version: "0.3.0")
        XCTAssertTrue(controller.shouldPresent)
    }

    func testDoesNotPresentWhenPermissionIsGranted() {
        let controller = OnboardingController(accessibility: StubAccessibility(isTrusted: true), preferences: makePreferences(), version: "0.3.0")
        XCTAssertFalse(controller.shouldPresent)
    }

    func testDoesNotExplainTwiceForTheSameVersion() {
        let preferences = makePreferences()
        let controller = OnboardingController(accessibility: StubAccessibility(isTrusted: false), preferences: preferences, version: "0.3.0")

        controller.markExplained()

        XCTAssertFalse(controller.shouldPresent, "an explanation the user dismissed is not repeated on every launch")
    }

    func testExplainsAgainAfterAnUpdate() {
        let preferences = makePreferences()
        OnboardingController(accessibility: StubAccessibility(isTrusted: false), preferences: preferences, version: "0.3.0").markExplained()

        let afterUpdate = OnboardingController(accessibility: StubAccessibility(isTrusted: false), preferences: preferences, version: "0.4.0")

        XCTAssertTrue(afterUpdate.shouldPresent, "updating an ad-hoc signed build invalidates the permission, so the user has to be told again")
    }

    func testSettingsURLPointsAtTheAccessibilityPane() {
        XCTAssertEqual(
            OnboardingController.accessibilitySettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }
}
