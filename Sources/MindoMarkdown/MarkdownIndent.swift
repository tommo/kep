import Foundation
import MindoBase

/// Backwards-compat shim — the indent helpers were promoted to
/// `MindoBase.EditorIndent` so plantuml could share them. Existing tests
/// that used `MarkdownIndent.indent / .outdent / .unit` keep working
/// through this wrapper.
public enum MarkdownIndent {
    public static let unit: String = EditorIndent.unit
    public static func indent(_ block: String) -> String { EditorIndent.indent(block) }
    public static func outdent(_ block: String) -> String { EditorIndent.outdent(block) }
}
