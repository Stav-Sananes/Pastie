// Sources/Pastie/Transforms/Transform.swift
import Foundation

/// A pure function from a clip's text to different text, applied on the way to being pasted.
/// A Transform never touches the store, never creates a Clip, and never performs I/O.
/// Returning nil means the input was not something this transform can handle (malformed JSON,
/// invalid base64); the caller surfaces that and pastes nothing. An empty result is `""`, not nil.
protocol Transform {
    /// The menu title. Must be unique across the registry.
    var name: String { get }
    func apply(_ input: String) -> String?
}

enum TransformRegistry {
    /// Menu order. Adding one here adds it to the ⌘T menu; nothing else needs changing.
    static let all: [any Transform] = [
        JSONPrettyPrintTransform(),
        UpperCaseTransform(),
        LowerCaseTransform(),
        TitleCaseTransform(),
        Base64EncodeTransform(),
        Base64DecodeTransform(),
        URLEncodeTransform(),
        URLDecodeTransform(),
        TrimWhitespaceTransform()
    ]
}
