// Tests/PastieTests/OnboardingControllerTests.swift
import XCTest
@testable import Pastie

private struct StubAccessibility: AccessibilityStatus {
    let isTrusted: Bool
}

final class OnboardingControllerTests: XCTestCase {
    func testPresentsWhenPermissionIsMissing() {
        let controller = OnboardingController(accessibility: StubAccessibility(isTrusted: false))
        XCTAssertTrue(controller.shouldPresent)
    }

    func testDoesNotPresentWhenPermissionIsGranted() {
        let controller = OnboardingController(accessibility: StubAccessibility(isTrusted: true))
        XCTAssertFalse(controller.shouldPresent)
    }

    func testSettingsURLPointsAtTheAccessibilityPane() {
        XCTAssertEqual(
            OnboardingController.accessibilitySettingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }
}
