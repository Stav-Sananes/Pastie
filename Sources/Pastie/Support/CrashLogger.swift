// Sources/Pastie/Support/CrashLogger.swift
import Foundation

/// Writes crash reports to a local directory. Nothing is transmitted anywhere.
enum CrashLogger {
    static var logDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Pastie/Logs", isDirectory: true)
    }

    static func write(_ contents: String, to directory: URL = logDirectory, date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("pastie-crash-\(stamp).log")
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Installs the uncaught-exception handler and handlers for the fatal signals a Swift app
    /// actually hits. Call once, at launch.
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let report = CrashLogFormatter.format(
                name: exception.name.rawValue,
                reason: exception.reason,
                stack: exception.callStackSymbols,
                date: Date()
            )
            try? CrashLogger.write(report)
        }

        for signalNumber in [SIGILL, SIGABRT, SIGFPE, SIGSEGV, SIGBUS] {
            signal(signalNumber) { received in
                let report = CrashLogFormatter.format(
                    name: "Signal \(received)",
                    reason: nil,
                    stack: Thread.callStackSymbols,
                    date: Date()
                )
                try? CrashLogger.write(report)
                // Restore the default handler and re-raise, so the process still dies the way
                // the system expects and Console still gets its own report.
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }
}
