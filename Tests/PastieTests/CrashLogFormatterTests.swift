// Tests/PastieTests/CrashLogFormatterTests.swift
import XCTest
@testable import Pastie

final class CrashLogFormatterTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_756_900_000)

    func testFormatIncludesNameReasonAndStack() {
        let output = CrashLogFormatter.format(
            name: "NSInvalidArgumentException",
            reason: "unrecognized selector sent to instance",
            stack: ["0 Pastie 0x1 -[Foo bar]", "1 AppKit 0x2 -[NSApplication run]"],
            date: fixedDate
        )

        XCTAssertTrue(output.contains("NSInvalidArgumentException"))
        XCTAssertTrue(output.contains("unrecognized selector sent to instance"))
        XCTAssertTrue(output.contains("-[Foo bar]"))
        XCTAssertTrue(output.contains("-[NSApplication run]"))
    }

    func testFormatHandlesAMissingReasonAndEmptyStack() {
        let output = CrashLogFormatter.format(name: "SIGSEGV", reason: nil, stack: [], date: fixedDate)

        XCTAssertTrue(output.contains("SIGSEGV"))
        XCTAssertTrue(output.contains("(no reason given)"))
        XCTAssertFalse(output.isEmpty)
    }

    func testWriteCreatesATimestampedFileInTheGivenDirectory() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)

        try CrashLogger.write("a crash happened", to: directory, date: fixedDate)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1)
        let contents = try String(contentsOf: directory.appendingPathComponent(files[0]), encoding: .utf8)
        XCTAssertEqual(contents, "a crash happened")
        XCTAssertTrue(files[0].hasSuffix(".log"))
    }
}
