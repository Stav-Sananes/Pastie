import Foundation

/// Holds the bytes of file clips received from peers, so pasting one on this
/// machine yields a real file rather than a path that means nothing here.
final class SyncedFileStore {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    static func defaultDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Pastie", isDirectory: true)
            .appendingPathComponent("SyncedFiles", isDirectory: true)
    }

    /// Writes `data` under a per-clip subdirectory so two peers sending different
    /// files with the same name cannot overwrite each other.
    func write(data: Data, clipUUID: String, fileName: String) throws -> String {
        let clipDirectory = directory.appendingPathComponent(sanitize(clipUUID), isDirectory: true)
        try FileManager.default.createDirectory(at: clipDirectory, withIntermediateDirectories: true)

        let destination = clipDirectory.appendingPathComponent(sanitize(fileName))
        try data.write(to: destination)
        return destination.path
    }

    /// Reduces an arbitrary peer-supplied string to a single safe path component.
    private func sanitize(_ name: String) -> String {
        let component = (name as NSString).lastPathComponent
        let cleaned = component
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "file"
        }
        return cleaned
    }
}
