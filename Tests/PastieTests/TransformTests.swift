// Tests/PastieTests/TransformTests.swift
import XCTest
@testable import Pastie

final class TransformTests: XCTestCase {
    private func apply(_ named: String, to input: String) -> String? {
        let transform = TransformRegistry.all.first { $0.name == named }
        XCTAssertNotNil(transform, "no transform named \(named)")
        return transform?.apply(input)
    }

    func testRegistryListsNineTransformsWithUniqueNames() {
        XCTAssertEqual(TransformRegistry.all.count, 9)
        let names = TransformRegistry.all.map { $0.name }
        XCTAssertEqual(Set(names).count, names.count, "menu titles must be unique")
    }

    func testJSONPrettyPrint() {
        let result = apply("JSON Pretty-Print", to: "{\"b\":2,\"a\":1}")
        XCTAssertEqual(result, "{\n  \"a\" : 1,\n  \"b\" : 2\n}")
    }

    func testJSONPrettyPrintRejectsMalformedInput() {
        XCTAssertNil(apply("JSON Pretty-Print", to: "{not json"))
    }

    func testCaseTransforms() {
        XCTAssertEqual(apply("Upper Case", to: "hello there"), "HELLO THERE")
        XCTAssertEqual(apply("Lower Case", to: "HELLO There"), "hello there")
        XCTAssertEqual(apply("Title Case", to: "hello there world"), "Hello There World")
    }

    func testBase64RoundTrip() {
        let encoded = apply("Base64 Encode", to: "hello")
        XCTAssertEqual(encoded, "aGVsbG8=")
        XCTAssertEqual(apply("Base64 Decode", to: "aGVsbG8="), "hello")
    }

    func testBase64DecodeRejectsGarbage() {
        XCTAssertNil(apply("Base64 Decode", to: "!!!not base64!!!"))
    }

    func testBase64DecodeRejectsValidBase64ThatIsNotText() {
        // 0xFF 0xFE is valid base64 but not valid UTF-8 — decoding must fail rather than
        // hand the user a replacement-character soup.
        let notText = Data([0xFF, 0xFE]).base64EncodedString()
        XCTAssertNil(apply("Base64 Decode", to: notText))
    }

    func testURLEncoding() {
        XCTAssertEqual(apply("URL Encode", to: "a b&c"), "a%20b%26c")
        XCTAssertEqual(apply("URL Decode", to: "a%20b%26c"), "a b&c")
    }

    func testURLDecodeRejectsBrokenEscapes() {
        XCTAssertNil(apply("URL Decode", to: "%zz"))
    }

    func testTrimWhitespace() {
        XCTAssertEqual(apply("Trim Whitespace", to: "  padded\n\n"), "padded")
    }

    func testEmptyResultIsAResultNotAFailure() {
        XCTAssertEqual(apply("Trim Whitespace", to: "   "), "", "empty is a valid result, not nil")
    }

    func testEveryTransformSurvivesEmptyInput() {
        for transform in TransformRegistry.all {
            _ = transform.apply("")  // must not crash; nil or a value are both acceptable
        }
    }
}
