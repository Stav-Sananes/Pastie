// Sources/Pastie/Support/CrashLogFormatter.swift
import Foundation

/// Pure formatting of a crash record. Separated from the handler so it can be tested — the
/// handler itself runs in a dying process and is not somewhere to discover a formatting bug.
enum CrashLogFormatter {
    static func format(name: String, reason: String?, stack: [String], date: Date) -> String {
        let timestamp = ISO8601DateFormatter().string(from: date)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        var lines = [
            "Pastie crash report",
            "Time: \(timestamp)",
            "Version: \(version)",
            "Exception: \(name)",
            "Reason: \(reason ?? "(no reason given)")",
            "",
            "Stack:"
        ]
        lines.append(contentsOf: stack.isEmpty ? ["(no stack available)"] : stack)
        return lines.joined(separator: "\n")
    }
}
