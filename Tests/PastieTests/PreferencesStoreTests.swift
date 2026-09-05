import XCTest
@testable import Pastie

final class PreferencesStoreTests: XCTestCase {
    func makeStore() -> PreferencesStore {
        PreferencesStore(defaults: UserDefaults(suiteName: "pastie-prefs-tests-\(UUID())")!)
    }

    func testRetentionCountDefaultsTo500() {
        XCTAssertEqual(makeStore().retentionCount, 500)
    }

    func testRetentionCountRoundTrips() {
        let store = makeStore()
        store.retentionCount = 1000
        XCTAssertEqual(store.retentionCount, 1000)
    }

    func testHotkeyDefaultsToOptionCommandV() {
        let store = makeStore()
        XCTAssertEqual(store.hotkeyKeyCode, 9) // kVK_ANSI_V
        let flags = NSEvent.ModifierFlags(rawValue: UInt(store.hotkeyModifiers))
        XCTAssertTrue(flags.contains(.option))
        XCTAssertTrue(flags.contains(.command))
    }

    func testExcludedBundleIDsRoundTrip() {
        let store = makeStore()
        store.excludedBundleIDs = ["com.1password.1password", "com.apple.keychainaccess"]
        XCTAssertEqual(store.excludedBundleIDs, ["com.1password.1password", "com.apple.keychainaccess"])
    }

    func testLaunchAtLoginDefaultsToFalse() {
        XCTAssertFalse(makeStore().launchAtLogin)
    }

    func testCaptureTypeTogglesDefaultToTrue() {
        let store = makeStore()
        XCTAssertTrue(store.captureText)
        XCTAssertTrue(store.captureImages)
        XCTAssertTrue(store.captureFiles)
    }

    func testCaptureTypeTogglesRoundTrip() {
        let store = makeStore()
        store.captureImages = false
        XCTAssertFalse(store.captureImages)
        XCTAssertTrue(store.captureText)
    }

    func testMaxImageSizeMBDefaultsTo5() {
        XCTAssertEqual(makeStore().maxImageSizeMB, 5)
    }

    func testMaxImageSizeMBRoundTrips() {
        let store = makeStore()
        store.maxImageSizeMB = 25
        XCTAssertEqual(store.maxImageSizeMB, 25)
    }

    func testPopupRowCountDefaultsTo8() {
        XCTAssertEqual(makeStore().popupRowCount, 8)
    }

    func testPopupRowCountRoundTrips() {
        let store = makeStore()
        store.popupRowCount = 12
        XCTAssertEqual(store.popupRowCount, 12)
    }

    func testRichPayloadDefaults() {
        let defaults = UserDefaults(suiteName: "PastieTests.rtf.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults)

        XCTAssertTrue(store.rtfCaptureEnabled, "keeping formatting is on by default")
        XCTAssertEqual(store.rtfSizeCapBytes, 1_048_576)
    }

    func testRichPayloadSettingsRoundTrip() {
        let defaults = UserDefaults(suiteName: "PastieTests.rtf.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults)

        store.rtfCaptureEnabled = false
        store.rtfSizeCapBytes = 4096

        XCTAssertFalse(store.rtfCaptureEnabled)
        XCTAssertEqual(store.rtfSizeCapBytes, 4096)
    }
}
