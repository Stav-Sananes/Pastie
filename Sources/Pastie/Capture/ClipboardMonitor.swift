import AppKit
import Foundation
import UniformTypeIdentifiers

final class ClipboardMonitor {
    private let store: ClipStore
    private let preferences: PreferencesStore
    private var lastChangeCount: Int
    private var timer: Timer?
    private let pollInterval: TimeInterval
    /// Set by ignoreNextChange() right before Pastie writes to the pasteboard itself
    /// (e.g. during paste). The next tick() that observes a changed pasteboard is
    /// treated as our own write rather than a new external copy, so it isn't captured.
    private var ignoringSelfWrite = false

    init(store: ClipStore, preferences: PreferencesStore, pollInterval: TimeInterval = 0.5) {
        self.store = store
        self.preferences = preferences
        self.pollInterval = pollInterval
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call right before Pastie writes a clip to the pasteboard (e.g. from PasteEngine) so the
    /// resulting pasteboard change is not re-captured as a brand-new clip on the next tick().
    func ignoreNextChange() {
        ignoringSelfWrite = true
    }

    func tick() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if ignoringSelfWrite {
            ignoringSelfWrite = false
            return
        }

        let types = Set((pasteboard.types ?? []).map { $0.rawValue })
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let context = CaptureContext(pasteboardTypes: types, frontmostBundleID: bundleID)
        guard CaptureFilter.shouldCapture(context: context, excludedBundleIDs: preferences.excludedBundleIDs) else {
            return
        }

        // Cheap type check (no decode) before the expensive read in makeClip() — a disabled
        // type shouldn't pay for a full image decode/downsample just to be discarded.
        guard let inferredType = inferClipType(from: pasteboard) else { return }
        guard CaptureFilter.isTypeEnabled(
            inferredType,
            captureText: preferences.captureText,
            captureImages: preferences.captureImages,
            captureFiles: preferences.captureFiles
        ) else { return }

        guard let clip = makeClip(from: pasteboard, sourceApp: bundleID) else { return }

        if let last = try? store.mostRecent(), last.hasSameContent(as: clip) {
            return
        }

        do {
            try store.insert(clip)
        } catch {
            NSLog("ClipboardMonitor: failed to insert clip: \(error)")
        }
    }

    /// What the pasteboard is actually offering, decided by the order the source declared its
    /// types in. NSPasteboard returns them richest-first as the owner declared them, and that
    /// order is the source telling you which representation it means.
    ///
    /// This matters because a text app hangs a placeholder image off a plain string copy —
    /// Terminal and Electron apps put a 4×4 pixel TIFF there — and a fixed image-before-text
    /// precedence would store that pixel and throw the copied text away.
    ///
    /// Only feasibility is checked, never a decode: the caller uses this to reject a disabled
    /// type before paying for a full image decode and downsample.
    func inferClipType(from pasteboard: NSPasteboard) -> ClipType? {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .file
        }
        for type in pasteboard.types ?? [] {
            guard let utType = UTType(type.rawValue) else { continue }
            if utType.conforms(to: .image) { return .image }
            if utType.conforms(to: .text) { return .text }
        }
        // Nothing declared a type we recognise — fall back to asking what can be read at all.
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) {
            return .image
        }
        if pasteboard.canReadObject(forClasses: [NSString.self], options: nil) {
            return .text
        }
        return nil
    }

    func makeClip(from pasteboard: NSPasteboard, sourceApp: String?) -> Clip? {
        let now = Date()
        switch inferClipType(from: pasteboard) {
        case .file:
            guard let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  let first = fileURLs.first, first.isFileURL else { return nil }
            return Clip(id: nil, type: .file, textContent: nil, imageData: nil, filePath: first.path, sourceApp: sourceApp, timestamp: now, saved: false, sortOrder: 0)
        case .image:
            if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation {
                let data = downsampleIfNeeded(tiff)
                return Clip(id: nil, type: .image, textContent: nil, imageData: data, filePath: nil, sourceApp: sourceApp, timestamp: now, saved: false, sortOrder: 0)
            }
            // The image type was declared but nothing decodable came back; a string beside it is
            // better than dropping the copy entirely.
            return textClip(from: pasteboard, sourceApp: sourceApp, now: now)
        case .text:
            return textClip(from: pasteboard, sourceApp: sourceApp, now: now)
        case .none:
            return nil
        }
    }

    private func textClip(from pasteboard: NSPasteboard, sourceApp: String?, now: Date) -> Clip? {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return nil }
        return Clip(id: nil, type: .text, textContent: text, imageData: nil, filePath: nil, sourceApp: sourceApp, timestamp: now, saved: false, sortOrder: 0, rtfData: richPayload(from: pasteboard))
    }

    /// The formatted representation to keep beside a text clip's plain string, or nil when the
    /// source offered none, the user turned it off, or it exceeds the cap. RTF only — never HTML,
    /// never the whole pasteboard item (ADR 0002).
    private func richPayload(from pasteboard: NSPasteboard) -> Data? {
        guard preferences.rtfCaptureEnabled else { return nil }
        guard let rtf = pasteboard.data(forType: .rtf) else { return nil }
        guard rtf.count <= preferences.rtfSizeCapBytes else {
            NSLog("ClipboardMonitor: dropping \(rtf.count)-byte RTF payload over the \(preferences.rtfSizeCapBytes)-byte cap")
            return nil
        }
        return rtf
    }

    private func downsampleIfNeeded(_ data: Data) -> Data {
        let thresholdBytes = preferences.maxImageSizeMB * 1024 * 1024
        guard data.count > thresholdBytes,
              let image = NSImage(data: data), image.size.width > 0 else { return data }
        let targetWidth: CGFloat = 400
        let targetSize = NSSize(width: targetWidth, height: targetWidth * (image.size.height / image.size.width))
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize))
        thumbnail.unlockFocus()
        return thumbnail.tiffRepresentation ?? data
    }
}
