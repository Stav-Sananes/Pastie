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
}
