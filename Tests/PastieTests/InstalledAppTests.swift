// Tests/PastieTests/InstalledAppTests.swift
import XCTest
@testable import Pastie

final class InstalledAppTests: XCTestCase {
    func testUnknownBundleIDFallsBackToTheIdentifierItself() {
        let app = InstalledApp.resolve("com.example.not.installed")

        XCTAssertEqual(app.bundleID, "com.example.not.installed")
        XCTAssertEqual(app.name, "com.example.not.installed", "an app that isn't installed still has to be nameable")
        XCTAssertFalse(app.isInstalled)
    }

    func testAnInstalledAppResolvesToItsNameAndIsMarkedInstalled() throws {
        // Finder ships with every macOS install; if this fails the test machine is not a Mac.
        let app = InstalledApp.resolve("com.apple.finder")

        XCTAssertTrue(app.isInstalled)
        XCTAssertNotEqual(app.name, "com.apple.finder", "an installed app shows its name, not its identifier")
        XCTAssertFalse(app.name.hasSuffix(".app"), "the .app suffix is not part of a name")
    }

    func testIdentityIsTheBundleIDSoListsCanKeyOnIt() {
        XCTAssertEqual(InstalledApp.resolve("com.example.a").id, "com.example.a")
    }
}
