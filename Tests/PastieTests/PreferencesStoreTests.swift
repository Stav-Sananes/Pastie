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
}
