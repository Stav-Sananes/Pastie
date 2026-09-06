// Sources/Pastie/OCR/VisionTextRecognizer.swift
import Foundation
import Vision

/// The only file in Pastie that imports Vision.
///
/// On-device text recognition: nothing is uploaded, and no entitlement is required. Failure is
/// always silent from the user's point of view — a clip that could not be read is simply not
/// searchable, which is exactly how every image clip behaved before this feature.
final class VisionTextRecognizer: TextRecognizing {
    /// Serial on purpose: a burst of copied screenshots should queue rather than start several
    /// CPU-heavy Vision requests at once.
    private let queue = DispatchQueue(label: "com.stav.pastie.ocr")

    func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void) {
        queue.async {
            completion(Self.recognize(imageData))
        }
    }

    private static func recognize(_ imageData: Data) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // The framework default is English-only (`recognitionLanguages = ["en-US"]`,
        // `automaticallyDetectsLanguage = false`), which would silently leave every
        // non-English screenshot unsearchable.
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("VisionTextRecognizer: recognition failed: \(error)")
            return nil
        }

        guard let observations = request.results else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
