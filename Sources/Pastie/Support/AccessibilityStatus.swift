// Sources/Pastie/Support/AccessibilityStatus.swift
import ApplicationServices

/// A seam over AXIsProcessTrusted(), which is a global C function and cannot be faked in tests.
protocol AccessibilityStatus {
    var isTrusted: Bool { get }
}

struct SystemAccessibilityStatus: AccessibilityStatus {
    var isTrusted: Bool { AXIsProcessTrusted() }
}
