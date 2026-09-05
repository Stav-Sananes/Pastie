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

    func testIsTypeEnabledRespectsTextToggle() {
        XCTAssertTrue(CaptureFilter.isTypeEnabled(.text, captureText: true, captureImages: false, captureFiles: false))
        XCTAssertFalse(CaptureFilter.isTypeEnabled(.text, captureText: false, captureImages: true, captureFiles: true))
    }

    func testIsTypeEnabledRespectsImageToggle() {
        XCTAssertTrue(CaptureFilter.isTypeEnabled(.image, captureText: false, captureImages: true, captureFiles: false))
        XCTAssertFalse(CaptureFilter.isTypeEnabled(.image, captureText: true, captureImages: false, captureFiles: true))
    }

    func testIsTypeEnabledRespectsFileToggle() {
        XCTAssertTrue(CaptureFilter.isTypeEnabled(.file, captureText: false, captureImages: false, captureFiles: true))
        XCTAssertFalse(CaptureFilter.isTypeEnabled(.file, captureText: true, captureImages: true, captureFiles: false))
    }
}
