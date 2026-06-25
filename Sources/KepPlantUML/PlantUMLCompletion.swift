import Foundation

/// Pure autocomplete logic for the PlantUML editor: given the partial word the
/// user has typed, return matching catalog entries (keywords, or skinparam
/// names when completing a `skinparam …` line). Case-insensitive prefix match;
/// an exact full match is dropped (nothing left to complete).
public enum PlantUMLCompletion {
    public static func completions(forPartialWord partial: String,
                                   lineUpToCaret: String = "") -> [String] {
        let p = partial.lowercased()
        guard !p.isEmpty else { return [] }

        // On a `skinparam ` line, the value being typed is a skinparam name.
        let trimmed = lineUpToCaret.lowercased().trimmingCharacters(in: .whitespaces)
        let skinparamContext = trimmed.hasPrefix("skinparam ") || trimmed == "skinparam"

        var pool = PlantUMLCatalog.keywords
        if skinparamContext { pool = PlantUMLCatalog.skinparams + pool }

        var seen = Set<String>()
        return pool.filter { kw in
            let low = kw.lowercased()
            // Match either the whole keyword or its bare word (after @/!/%),
            // since NSTextView's partial-word range excludes leading punctuation.
            let bare = low.drop { "@!%".contains($0) }
            guard low.hasPrefix(p) || bare.hasPrefix(p) else { return false }
            guard low != p else { return false }
            return seen.insert(low).inserted
        }
    }
}
