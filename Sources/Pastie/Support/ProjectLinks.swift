import Foundation

/// The places Pastie points people to from inside the app: the source, the issue tracker, the
/// licence and the tip jar. One place to change when any of them moves.
enum ProjectLinks {
    static let sourceRepository = URL(string: "https://github.com/Stav-Sananes/Pastie")!
    static let issues = URL(string: "https://github.com/Stav-Sananes/Pastie/issues")!
    static let licence = URL(string: "https://github.com/Stav-Sananes/Pastie/blob/main/LICENSE")!
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/stav_sananes")!

    /// The marketing version from Info.plist, or "unknown" when running outside a bundle (tests).
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
