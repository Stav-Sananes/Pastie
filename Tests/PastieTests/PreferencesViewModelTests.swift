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

        vm.addExcluded(bundleIDs: ["com.zzz.app"])
        vm.addExcluded(bundleIDs: ["com.aaa.app"])

        XCTAssertEqual(vm.excludedBundleIDs, ["com.aaa.app", "com.zzz.app"])
    }

    func testAddExcludedTakesSeveralAppsAtOnce() {
        let vm = makeViewModel()

        vm.addExcluded(bundleIDs: ["com.zzz.app", "com.aaa.app"])

        XCTAssertEqual(vm.excludedBundleIDs, ["com.aaa.app", "com.zzz.app"], "the picker allows a multiple selection")
    }

    func testAddExcludedIgnoresBlankAndDuplicate() {
        let vm = makeViewModel()

        vm.addExcluded(bundleIDs: ["com.example.app"])
        vm.addExcluded(bundleIDs: ["com.example.app", "   ", ""])

        XCTAssertEqual(vm.excludedBundleIDs, ["com.example.app"])
    }

    func testRemoveExcluded() {
        let vm = makeViewModel()
        vm.addExcluded(bundleIDs: ["com.example.app"])

        vm.removeExcluded(at: IndexSet(integer: 0))

        XCTAssertTrue(vm.excludedBundleIDs.isEmpty)
    }

    func testRemoveExcludedByBundleID() {
        let vm = makeViewModel()
        vm.addExcluded(bundleIDs: ["com.a.app", "com.b.app"])

        vm.removeExcluded(bundleIDs: ["com.a.app"])

        XCTAssertEqual(vm.excludedBundleIDs, ["com.b.app"], "the list removes what the selection names, not an index it guessed")
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
        XCTAssertEqual(store.hotkeyModifiers, UInt32(NSEvent.ModifierFlags([.control, .shift]).rawValue))
    }

    func testRichPayloadSettingsWriteThroughToTheStore() {
        let defaults = UserDefaults(suiteName: "PastieTests.vm.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults)
        let viewModel = PreferencesViewModel(store: store)

        viewModel.rtfCaptureEnabled = false
        viewModel.rtfSizeCapMB = 4

        XCTAssertFalse(store.rtfCaptureEnabled)
        XCTAssertEqual(store.rtfSizeCapBytes, 4 * 1_048_576)
    }

    func testRichPayloadCapIsClampedToASaneRange() {
        let defaults = UserDefaults(suiteName: "PastieTests.vm.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults)
        let viewModel = PreferencesViewModel(store: store)

        viewModel.rtfSizeCapMB = 0
        XCTAssertEqual(store.rtfSizeCapBytes, 1_048_576, "0 MB would silently disable rich payloads")

        viewModel.rtfSizeCapMB = 999
        XCTAssertEqual(store.rtfSizeCapBytes, 25 * 1_048_576, "capped at 25MB")
    }
}
