import Foundation

extension Topic {
    /// Parse a topic subtree from `lexer` (positioned just past `---`). Returns the root topic.
    /// Mirrors `Topic.parse(...)` from the Java original.
    static func parse(map: MindMap?, lexer: inout MmdLexer) throws -> Topic? {
        var rootTopic: Topic? = nil      // strong ref to the root so the tree stays alive
        var topic: Topic? = nil          // strong ref to the most recently created topic
        var depth = 0
        var detectedLevel = -1
        var extraType: ExtraType? = nil

        var codeSnippetLanguage: String? = nil
        var codeSnippetBody: String? = nil

        while true {
            let oldOffset = lexer.offset
            lexer.advance()
            if lexer.offset == oldOffset || lexer.tokenType == nil { break }

            switch lexer.tokenType! {
            case .topicLevel:
                detectedLevel = ModelUtils.calcLeadingHashes(lexer.tokenText)

            case .topicTitle:
                let raw = ModelUtils.removeISOControls(lexer.tokenText)
                let trimmedNewline = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
                // Strip the leading single space that follows the `#` markers.
                let body = trimmedNewline.hasPrefix(" ") ? String(trimmedNewline.dropFirst()) : trimmedNewline
                let newText = ModelUtils.unescapeMarkdown(body)

                if let t = topic {
                    // Existing tree — pick the insertion site based on
                    // detectedLevel relative to the current depth.
                    if detectedLevel == depth + 1 {
                        depth = detectedLevel
                        topic = t.addChild(text: newText)
                    } else if detectedLevel == depth, let parent = t.parent {
                        topic = parent.addChild(text: newText)
                    } else if detectedLevel < depth, let parent = t.findParent(forDepth: depth - detectedLevel) {
                        topic = parent.addChild(text: newText)
                        depth = detectedLevel
                    }
                } else {
                    // First topicTitle — becomes the root. Sync depth so the
                    // next sibling/child math against this root works.
                    let r = Topic(text: newText, parent: nil, map: map)
                    rootTopic = r
                    topic = r
                    depth = detectedLevel
                }

            case .extraType:
                // Token text starts with `-`; strip and trim to get NOTE/LINK/etc.
                let name = String(lexer.tokenText.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                extraType = ExtraType.from(token: name)

            case .codeSnippetStart:
                if topic != nil {
                    let lang = String(lexer.tokenText.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    codeSnippetLanguage = lang
                    codeSnippetBody = ""
                }

            case .codeSnippetBody:
                codeSnippetBody = (codeSnippetBody ?? "") + lexer.tokenText

            case .codeSnippetEnd:
                if let t = topic, let lang = codeSnippetLanguage {
                    // Drop the single newline the serializer inserts between the
                    // body and the closing fence — otherwise every save/load
                    // grows the snippet a trailing "\n" (fenced-block content,
                    // by convention, excludes that final separator newline).
                    var body = codeSnippetBody ?? ""
                    if body.hasSuffix("\r\n") { body.removeLast(2) }
                    else if body.hasSuffix("\n") { body.removeLast() }
                    t.putCodeSnippet(language: lang, body: body)
                }
                codeSnippetLanguage = nil
                codeSnippetBody = nil

            case .attribute:
                if let t = topic {
                    let line = lexer.tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                    var attrs: [String: String] = [:]
                    MindMap.fillMapByAttributes(line: line, into: &attrs)
                    t.putAttributes(attrs)
                }
                extraType = nil

            case .extraText:
                if let t = topic, let kind = extraType {
                    let raw = lexer.tokenText
                    // Drop `<pre>` (5) ... `</pre>` (6).
                    if raw.count >= 11 {
                        let body = String(raw.dropFirst(5).dropLast(6))
                        if let processed = kind.preprocess(body) {
                            let extra = kind.parseLoaded(value: processed, attributes: t.attributes)
                            t.setExtra(extra)
                        }
                    }
                }
                extraType = nil

            case .unknownLine:
                if topic != nil, extraType != nil {
                    extraType = nil
                }

            default:
                continue
            }
        }
        return rootTopic
    }
}
