import XCTest
@testable import Pastie

final class CaptureFilterTests: XCTestCase {
    func testAllowsOrdinaryText() {
        let context = CaptureContext(pasteboardTypes: ["public.utf8-plain-text"], frontmostBundleID: "com.apple.TextEdit")
        XCTAssertTrue(CaptureFilter.shouldCapture(context: context, excludedBundleIDs: []))
    }

    func testBlocksConcealedType() {
        let context = CaptureContext(pasteboardTypes: ["org.nspasteboard.ConcealedType", "public.utf8-plain-text"], frontmostBundleID: "com.agilebits.onepassword7")
        XCTAssertFalse(CaptureFilter.shouldCapture(context: context, excludedBundleIDs: []))
    }

    func testBlocksTransientType() {
        let context = CaptureContext(pasteboardTypes: ["org.nspasteboard.TransientType"], frontmostBundleID: nil)
        XCTAssertFalse(CaptureFilter.shouldCapture(context: context, excludedBundleIDs: []))
    }

    func testBlocksExcludedApp() {
        let context = CaptureContext(pasteboardTypes: ["public.utf8-plain-text"], frontmostBundleID: "com.1password.1password")
        XCTAssertFalse(CaptureFilter.shouldCapture(context: context, excludedBundleIDs: ["com.1password.1password"]))
    }
}
