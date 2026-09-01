// Sources/Pastie/Search/ClipSearch.swift
import Foundation

enum ClipSearch {
    static func filter(_ clips: [Clip], query: String) -> [Clip] {
        guard !query.isEmpty else { return clips }
        let lowered = query.lowercased()
        return clips.filter { clip in
            switch clip.type {
            case .text: return clip.textContent?.lowercased().contains(lowered) ?? false
            case .file: return clip.filePath?.lowercased().contains(lowered) ?? false
            case .image: return false
            }
        }
    }
}
