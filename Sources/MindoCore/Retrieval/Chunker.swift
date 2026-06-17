import Foundation

/// Splits a document into retrieval-sized text chunks. Paragraph-aware (splits
/// on blank lines), greedily packing paragraphs into ≤`maxChars` windows with a
/// trailing-character `overlap` carried into the next chunk so a passage that
/// straddles a boundary still embeds with context. Pure → unit-testable.
public enum Chunker {
    public static func chunks(of text: String, maxChars: Int = 800, overlap: Int = 120) -> [String] {
        let maxChars = max(1, maxChars)
        let overlap = max(0, min(overlap, maxChars - 1))

        // Paragraphs = runs separated by one or more blank lines.
        let paragraphs = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(trimmed) }
            // Carry the tail as overlap into the next window.
            current = overlap > 0 && trimmed.count > overlap ? String(trimmed.suffix(overlap)) + "\n" : ""
        }

        for para in paragraphs {
            // A single oversized paragraph is hard-split into maxChars windows.
            if para.count > maxChars {
                if !current.isEmpty { flush() }
                var idx = para.startIndex
                while idx < para.endIndex {
                    let end = para.index(idx, offsetBy: maxChars, limitedBy: para.endIndex) ?? para.endIndex
                    chunks.append(String(para[idx..<end]))
                    idx = end
                }
                current = ""
                continue
            }
            if current.count + para.count + 1 > maxChars { flush() }
            current += (current.isEmpty ? "" : "\n") + para
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { chunks.append(tail) }
        return chunks
    }
}
