import Foundation

struct CaptureContext {
    let pasteboardTypes: Set<String>
    let frontmostBundleID: String?
}

enum CaptureFilter {
    static let concealedType = "org.nspasteboard.ConcealedType"
    static let transientType = "org.nspasteboard.TransientType"

    static func shouldCapture(context: CaptureContext, excludedBundleIDs: Set<String>) -> Bool {
        if context.pasteboardTypes.contains(concealedType) || context.pasteboardTypes.contains(transientType) {
            return false
        }
        if let bundleID = context.frontmostBundleID, excludedBundleIDs.contains(bundleID) {
            return false
        }
        return true
    }

    /// Gates a clip by its type against the user's per-type capture toggles. Checked
    /// AFTER shouldCapture() and after the clip is built — shouldCapture() covers
    /// privacy signals (concealed/transient, excluded app) that must block reading
    /// pasteboard content at all; this only decides whether to store what was read.
    static func isTypeEnabled(_ type: ClipType, captureText: Bool, captureImages: Bool, captureFiles: Bool) -> Bool {
        switch type {
        case .text: return captureText
        case .image: return captureImages
        case .file: return captureFiles
        }
    }
}
