// Sources/Pastie/OCR/TextRecognizing.swift
import Foundation

/// Reads text out of image bytes. The seam that keeps Vision out of the capture path's tests.
///
/// `completion` is called on an unspecified queue — callers that touch UI must hop themselves.
/// A nil result means "nothing searchable came back": no text found, or recognition failed.
/// The two are not distinguished because no caller benefits from telling them apart.
protocol TextRecognizing {
    func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void)
}
