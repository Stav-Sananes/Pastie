import AppKit
import Foundation

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

    /// Mirrors makeClip()'s file → image → text precedence, but only checks feasibility
    /// (canReadObject) instead of materializing the object — so the type gate above can
    /// reject a disabled type before paying for a full image decode/downsample.
    private func inferClipType(from pasteboard: NSPasteboard) -> ClipType? {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .file
        }
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) {
            return .image
        }
        if pasteboard.canReadObject(forClasses: [NSString.self], options: nil) {
            return .text
        }
        return nil
    }

    private func makeClip(from pasteboard: NSPasteboard, sourceApp: String?) -> Clip? {
        let now = Date()
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = fileURLs.first, first.isFileURL {
            return Clip(id: nil, type: .file, textContent: nil, imageData: nil, filePath: first.path, sourceApp: sourceApp, timestamp: now, saved: false, sortOrder: 0)
        }
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation {
            let data = downsampleIfNeeded(tiff)
            return Clip(id: nil, type: .image, textContent: nil, imageData: data, filePath: nil, sourceApp: sourceApp, timestamp: now, saved: false, sortOrder: 0)
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return Clip(id: nil, type: .text, textContent: text, imageData: nil, filePath: nil, sourceApp: sourceApp, timestamp: now, saved: false, sortOrder: 0)
        }
        return nil
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
