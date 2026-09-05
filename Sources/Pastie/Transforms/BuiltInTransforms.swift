// Sources/Pastie/Transforms/BuiltInTransforms.swift
import Foundation

struct JSONPrettyPrintTransform: Transform {
    let name = "JSON Pretty-Print"
    func apply(_ input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
}

struct UpperCaseTransform: Transform {
    let name = "Upper Case"
    func apply(_ input: String) -> String? { input.uppercased() }
}

struct LowerCaseTransform: Transform {
    let name = "Lower Case"
    func apply(_ input: String) -> String? { input.lowercased() }
}

struct TitleCaseTransform: Transform {
    let name = "Title Case"
    func apply(_ input: String) -> String? { input.capitalized }
}

struct Base64EncodeTransform: Transform {
    let name = "Base64 Encode"
    func apply(_ input: String) -> String? {
        input.data(using: .utf8)?.base64EncodedString()
    }
}

struct Base64DecodeTransform: Transform {
    let name = "Base64 Decode"
    func apply(_ input: String) -> String? {
        // Both guards matter: the input may not be base64 at all, or may decode to bytes that
        // aren't text. Either way the user gets a failure message rather than mojibake.
        guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}

struct URLEncodeTransform: Transform {
    let name = "URL Encode"
    func apply(_ input: String) -> String? {
        // .urlQueryAllowed leaves & and = unescaped, which is wrong for a value being encoded.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return input.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}

struct URLDecodeTransform: Transform {
    let name = "URL Decode"
    func apply(_ input: String) -> String? { input.removingPercentEncoding }
}

struct TrimWhitespaceTransform: Transform {
    let name = "Trim Whitespace"
    func apply(_ input: String) -> String? {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
