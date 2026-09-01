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
}
