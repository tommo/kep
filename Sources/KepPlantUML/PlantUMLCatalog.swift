import Foundation

/// PlantUML language data for the editor — keywords (autocomplete + syntax
/// highlighting), skinparam names, and canonical per-diagram snippets.
/// Sourced from a research pass across every PlantUML diagram type, curated to
/// single-token keywords (multi-word phrases / symbols dropped) and HTML-
/// unescaped snippet bodies.
public enum PlantUMLCatalog {

    /// Single-token keywords/element names a user types. Includes the
    /// @start.../@end... pair names, !preprocessor directives, %functions, and
    /// plain element/control words. Lowercased except the @/!/% prefixes.
    public static let keywords: [String] = [
        // diagram pairs
        "@startuml", "@enduml", "@startmindmap", "@endmindmap", "@startwbs", "@endwbs",
        "@startgantt", "@endgantt", "@startjson", "@endjson", "@startyaml", "@endyaml",
        "@startsalt", "@endsalt",
        // preprocessor
        "!define", "!definelong", "!enddefinelong", "!function", "!endfunction",
        "!procedure", "!endprocedure", "!if", "!else", "!elseif", "!endif",
        "!ifdef", "!ifndef", "!while", "!endwhile", "!include", "!includeurl",
        "!includesub", "!include_many", "!import", "!local", "!log", "!pragma",
        "!return", "!startsub", "!endsub", "!theme", "!undef", "!unquoted", "!assert",
        // %builtin functions
        "%date", "%dirpath", "%feature", "%filename", "%function", "%getenv",
        "%intval", "%lower", "%now", "%strlen", "%string", "%substr", "%upper",
        // elements
        "actor", "participant", "boundary", "control", "entity", "collections",
        "queue", "database", "class", "interface", "abstract", "annotation",
        "enum", "object", "component", "node", "cloud", "frame", "folder",
        "rectangle", "package", "namespace", "usecase", "state", "artifact",
        "agent", "card", "file", "person", "storage", "stack", "hexagon",
        "diamond", "circle", "port", "portin", "portout", "map", "json",
        // relations / control
        "extends", "implements", "as", "note", "hnote", "rnote", "ref",
        "activate", "deactivate", "create", "destroy", "autonumber", "newpage",
        "alt", "opt", "loop", "par", "break", "critical", "group", "box",
        "if", "else", "elseif", "endif", "while", "endwhile", "repeat", "fork",
        "again", "split", "detach", "start", "stop", "end", "partition",
        "switch", "case", "endswitch", "goto", "label", "swimlane", "return",
        // styling / meta
        "skinparam", "skin", "hide", "show", "remove", "title", "caption",
        "legend", "endlegend", "footer", "header", "scale", "order", "stereotype",
        "left", "right", "top", "bottom", "of", "over", "on", "link",
        "allowmixing", "scroll", "printscale", "milestone", "separator", "divider",
        // gantt words
        "happens", "lasts", "starts", "ends", "after", "today", "between",
        "daily", "weekly", "monthly", "day", "days", "week", "weeks", "month",
        // boolean / misc
        "true", "false", "and", "is", "then", "backward", "color",
    ]

    /// Case-insensitive regex alternation matching any catalog keyword as a
    /// whole token. Drives `PlantUMLHighlighter` so syntax highlighting tracks
    /// the SAME vocabulary as autocompletion. Symbol-prefixed keywords (@/!/%)
    /// don't get a leading `\b` (no word boundary before a symbol); all get a
    /// trailing `\b` so `if` doesn't shadow `ifdef`.
    public static var keywordRegexPattern: String {
        func esc(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }
        let prefixed = keywords.filter { ($0.first).map { "@!%".contains($0) } ?? false }
        let plain = keywords.filter { !(($0.first).map { "@!%".contains($0) } ?? false) }
        var alts: [String] = []
        if !plain.isEmpty { alts.append("\\b(?:" + plain.map(esc).joined(separator: "|") + ")\\b") }
        if !prefixed.isEmpty { alts.append("(?:" + prefixed.map(esc).joined(separator: "|") + ")\\b") }
        return "(?i)(?:" + alts.joined(separator: "|") + ")"
    }

    /// Common `skinparam <name>` names for completion after `skinparam `.
    public static let skinparams: [String] = [
        "backgroundColor", "handwritten", "monochrome", "shadowing", "roundCorner",
        "defaultFontName", "defaultFontSize", "defaultFontColor", "linetype",
        "ranksep", "nodesep", "dpi", "padding", "fontName", "fontSize",
        "fontColor", "fontStyle", "borderColor", "arrowColor", "componentStyle",
        "sequenceMessageAlign", "wrapWidth",
    ]

    public struct Snippet: Equatable, Sendable {
        public let category: String
        public let title: String
        public let body: String
    }

    /// Canonical starter snippets — HTML-unescaped, grouped by category.
    public static let snippets: [Snippet] = rawSnippets.map {
        Snippet(category: $0.0, title: $0.1, body: htmlUnescape($0.2))
    }

    /// Snippets grouped by `category`, preserving first-seen category order —
    /// drives the categorized insert submenus.
    public static var groupedSnippets: [(category: String, snippets: [Snippet])] {
        var order: [String] = []
        var buckets: [String: [Snippet]] = [:]
        for s in snippets {
            if buckets[s.category] == nil { order.append(s.category) }
            buckets[s.category, default: []].append(s)
        }
        return order.map { ($0, buckets[$0]!) }
    }

    /// HTML-unescape the researched snippet bodies (`&gt;`→`>`, …). `&amp;` is
    /// decoded last so doubly-escaped sequences resolve correctly.
    public static func htmlUnescape(_ s: String) -> String {
        var out = s
        for (e, c) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            out = out.replacingOccurrences(of: e, with: c)
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static let rawSnippets: [(String, String, String)] = [
        // MARK: Diagram
        ("Diagram", "Sequence", "@startuml\nparticipant Alice\nparticipant Bob\n\nAlice -&gt; Bob: Request\nactivate Bob\nBob --&gt; Alice: Response\ndeactivate Bob\n\nalt success\n  Alice -&gt; Bob: Another request\nelse failure\n  Bob --&gt; Alice: error\nend\n@enduml"),
        ("Diagram", "Class", "@startuml\nabstract class AbstractList\ninterface List\n\nclass ArrayList {\n  - int size\n  + void add(Object o)\n  + Object get(int i)\n}\n\nAbstractList &lt;|-- ArrayList\nList &lt;|.. ArrayList\n@enduml"),
        ("Diagram", "Activity", "@startuml\nstart\n:read input;\nif (valid?) then (yes)\n  :process;\nelse (no)\n  :error;\nendif\n:write output;\nstop\n@enduml"),
        ("Diagram", "State", "@startuml\n[*] --&gt; Idle\nstate Active {\n  [*] --&gt; Running\n  Running --&gt; Paused : pause\n}\nIdle --&gt; Active : start\nActive --&gt; [*] : shutdown\n@enduml"),
        ("Diagram", "Use Case", "@startuml\nleft to right direction\nactor User as u\nrectangle System {\n  usecase \"Login\" as UC1\n  usecase \"Manage\" as UC2\n}\nu --&gt; UC1\nUC2 ..&gt; UC1 : &lt;&lt;include&gt;&gt;\n@enduml"),
        ("Diagram", "Component", "@startuml\npackage \"Frontend\" {\n  [Web App] as web\n}\npackage \"Backend\" {\n  [API] as api\n  database \"DB\" as db\n}\nweb --&gt; api\napi --&gt; db\n@enduml"),
        ("Diagram", "Deployment", "@startuml\nnode \"Web Server\" as web {\n  artifact app.war\n}\ndatabase \"PostgreSQL\" as db\nweb --&gt; db : JDBC\n@enduml"),
        ("Diagram", "Entity Relationship", "@startuml\nhide circle\nskinparam linetype ortho\nentity User {\n  *id : number &lt;&lt;PK&gt;&gt;\n  --\n  name : text\n}\nentity Order {\n  *id : number &lt;&lt;PK&gt;&gt;\n  *user_id : number &lt;&lt;FK&gt;&gt;\n}\nUser ||--o{ Order : places\n@enduml"),
        ("Diagram", "Object", "@startuml\nobject Account\nobject User {\n  name = \"Alice\"\n  age = 30\n}\nUser --&gt; Account : owns\n@enduml"),
        ("Diagram", "Gantt", "@startgantt\nProject starts 2024-01-01\n[Design] lasts 10 days\n[Build] lasts 15 days\n[Build] starts after [Design]'s end\n[Build] is 40% completed\n@endgantt"),
        ("Diagram", "Work Breakdown", "@startwbs\n* Project\n** Phase 1\n*** Task A\n*** Task B\n** Phase 2\n@endwbs"),
        ("Diagram", "Mindmap", "@startmindmap\n* Root\n** Branch A\n*** Leaf A1\n** Branch B\n@endmindmap"),
        ("Diagram", "JSON", "@startjson\n{\n  \"name\": \"PlantUML\",\n  \"tags\": [\"json\", \"yaml\"],\n  \"owner\": { \"id\": 42 }\n}\n@endjson"),
        ("Diagram", "YAML", "@startyaml\nname: PlantUML\nformats:\n  - json\n  - yaml\n@endyaml"),
        ("Diagram", "Salt (wireframe)", "@startsalt\n{\n  Login    | \"MyName  \"\n  Password | \"****    \"\n  [Cancel] | [  OK  ]\n}\n@endsalt"),

        // MARK: Styling
        ("Styling", "Theme + skinparam", "@startuml\n!theme plain\nskinparam backgroundColor #FEFEFE\nskinparam shadowing false\nskinparam roundCorner 10\nclass Foo\nclass Bar\nFoo --&gt; Bar\n@enduml"),
        ("Styling", "Colors & stereotypes", "@startuml\nskinparam class {\n  BackgroundColor PaleGreen\n  BorderColor DarkGreen\n  ArrowColor SeaGreen\n}\nclass Foo #LightBlue;line:blue;text:navy\nclass Bar #pink\nFoo --&gt; Bar\n@enduml"),
        ("Styling", "Named theme", "@startuml\n!theme cerulean\ntitle Themed diagram\nclass A\nclass B\nA --&gt; B\n@enduml"),

        // MARK: Notes & Text
        ("Notes & Text", "Notes", "@startuml\nAlice -&gt; Bob : hello\nnote left: a note on the left\nnote right of Bob\n  multi-line\n  note\nend note\nhnote over Alice : highlighted\n@enduml"),
        ("Notes & Text", "Creole formatting", "@startuml\nnote as N\n  = Heading\n  This is **bold**, //italic//, \"\"monospace\"\".\n  * bullet one\n  * bullet two\n  [[https://plantuml.com link]]\nend note\n@enduml"),

        // MARK: Advanced
        ("Advanced", "Preprocessor", "@startuml\n!function $double($x)\n  !return $x * 2\n!endfunction\nAlice -&gt; Bob : %intval($double(2))\n@enduml"),
        ("Advanced", "C4 container", "@startuml\n!include &lt;C4/C4_Container&gt;\nPerson(user, \"User\")\nContainer(web, \"Web App\", \"Swift\")\nSystem_Ext(api, \"External API\")\nRel(user, web, \"Uses\")\nRel(web, api, \"Calls\", \"HTTPS\")\n@enduml"),
        ("Advanced", "FontAwesome icons", "@startuml\n!include &lt;font-awesome-5/server&gt;\n!include &lt;font-awesome-5/database&gt;\nrectangle \"&lt;$server&gt;\\nServer\" as s\ndatabase \"&lt;$database&gt;\\nDB\" as d\ns --&gt; d\n@enduml"),
    ]
}
