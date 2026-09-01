import XCTest
@testable import Pastie

final class SyncedFileStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pastie-file-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWritesFileAndReturnsReadablePath() throws {
        let store = SyncedFileStore(directory: tempDir)
        let bytes = Data("report contents".utf8)

        let path = try store.write(data: bytes, clipUUID: "uuid-1", fileName: "report.pdf")

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), bytes)
        XCTAssertTrue(path.hasSuffix("report.pdf"), "original filename should be preserved")
    }

    func testCreatesDirectoryIfMissing() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))
        let store = SyncedFileStore(directory: tempDir)

        _ = try store.write(data: Data("x".utf8), clipUUID: "uuid-2", fileName: "a.txt")

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
    }

    func testSanitizesPathSeparatorsInFileName() throws {
        let store = SyncedFileStore(directory: tempDir)

        let path = try store.write(data: Data("x".utf8), clipUUID: "uuid-3", fileName: "../../etc/passwd")

        XCTAssertTrue(path.hasPrefix(tempDir.path), "written file must stay inside the store directory")
        XCTAssertFalse(path.contains(".."), "path traversal segments must be stripped")
    }

    func testEmptyFileNameFallsBackToPlaceholder() throws {
        let store = SyncedFileStore(directory: tempDir)

        let path = try store.write(data: Data("x".utf8), clipUUID: "uuid-4", fileName: "")

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testDistinctClipsDoNotCollideOnSameFileName() throws {
        let store = SyncedFileStore(directory: tempDir)

        let first = try store.write(data: Data("one".utf8), clipUUID: "uuid-5", fileName: "same.txt")
        let second = try store.write(data: Data("two".utf8), clipUUID: "uuid-6", fileName: "same.txt")

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: first)), Data("one".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: second)), Data("two".utf8))
    }
}
