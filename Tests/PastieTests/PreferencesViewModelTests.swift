import AppKit
import XCTest
@testable import Pastie

final class PreferencesViewModelTests: XCTestCase {
    func makeViewModel() -> PreferencesViewModel {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-vm-tests-\(UUID())")!)
        return PreferencesViewModel(store: store)
    }

    func testAddExcludedAppendsAndSorts() {
        let vm = makeViewModel()
        vm.newBundleID = "com.zzz.app"
        vm.addExcluded()
        vm.newBundleID = "com.aaa.app"
        vm.addExcluded()

        XCTAssertEqual(vm.excludedBundleIDs, ["com.aaa.app", "com.zzz.app"])
        XCTAssertEqual(vm.newBundleID, "")
    }

    func testAddExcludedIgnoresBlankAndDuplicate() {
        let vm = makeViewModel()
        vm.newBundleID = "com.example.app"
        vm.addExcluded()
        vm.newBundleID = "com.example.app"
        vm.addExcluded()
        vm.newBundleID = "   "
        vm.addExcluded()

        XCTAssertEqual(vm.excludedBundleIDs, ["com.example.app"])
    }

    func testRemoveExcluded() {
        let vm = makeViewModel()
        vm.newBundleID = "com.example.app"
        vm.addExcluded()

        vm.removeExcluded(at: IndexSet(integer: 0))

        XCTAssertTrue(vm.excludedBundleIDs.isEmpty)
    }

    func testCaptureTogglesDefaultToTrueAndRoundTrip() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.captureText)
        XCTAssertTrue(vm.captureImages)
        XCTAssertTrue(vm.captureFiles)
        vm.captureImages = false
        XCTAssertFalse(vm.captureImages)
    }

    func testUpdateHotkeyUpdatesDisplayAndFiresCallback() {
        var changed = false
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-vm-hotkey-tests-\(UUID())")!)
        let vm = PreferencesViewModel(store: store, onHotkeyChanged: { changed = true })

        vm.updateHotkey(keyCode: 1, modifiers: UInt32(NSEvent.ModifierFlags([.control, .shift]).rawValue))

        XCTAssertEqual(vm.hotkeyDisplay, "⌃⇧S")
        XCTAssertTrue(changed)
        XCTAssertEqual(store.hotkeyKeyCode, 1)
    }
}
