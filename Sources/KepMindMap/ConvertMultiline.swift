import Foundation

/// Pure-logic line splitter for the "Convert to Subtree" topic command.
/// Splits on `\n`, trims surrounding whitespace, and drops empty/whitespace-
/// only lines so the resulting children carry actual text. Lives outside
/// MindMapView so the splitting rule is unit-testable in isolation.
public enum ConvertMultiline {
    public static func split(_ text: String) -> [String] {
        return text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
