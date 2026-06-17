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

    /// Common `skinparam <name>` names for completion after `skinparam `.
    public static let skinparams: [String] = [
        "backgroundColor", "handwritten", "monochrome", "shadowing", "roundCorner",
        "defaultFontName", "defaultFontSize", "defaultFontColor", "linetype",
        "ranksep", "nodesep", "dpi", "padding", "fontName", "fontSize",
        "fontColor", "fontStyle", "borderColor", "arrowColor", "componentStyle",
        "sequenceMessageAlign", "wrapWidth",
    ]

    public struct Snippet: Equatable, Sendable {
        public let title: String
        public let body: String
    }

    /// Canonical starter snippets, one per diagram type — HTML-unescaped.
    public static let snippets: [Snippet] = rawSnippets.map {
        Snippet(title: $0.0, body: htmlUnescape($0.1))
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

    private static let rawSnippets: [(String, String)] = [
        ("Sequence", "@startuml\nparticipant Alice\nparticipant Bob\n\nAlice -&gt; Bob: Request\nactivate Bob\nBob --&gt; Alice: Response\ndeactivate Bob\n\nalt success\n  Alice -&gt; Bob: Another request\nelse failure\n  Bob --&gt; Alice: error\nend\n@enduml"),
        ("Class", "@startuml\nabstract class AbstractList\ninterface List\n\nclass ArrayList {\n  - int size\n  + void add(Object o)\n  + Object get(int i)\n}\n\nAbstractList &lt;|-- ArrayList\nList &lt;|.. ArrayList\n@enduml"),
        ("Activity", "@startuml\nstart\n:read input;\nif (valid?) then (yes)\n  :process;\nelse (no)\n  :error;\nendif\n:write output;\nstop\n@enduml"),
        ("State", "@startuml\n[*] --&gt; Idle\nstate Active {\n  [*] --&gt; Running\n  Running --&gt; Paused : pause\n}\nIdle --&gt; Active : start\nActive --&gt; [*] : shutdown\n@enduml"),
        ("Use Case", "@startuml\nleft to right direction\nactor User as u\nrectangle System {\n  usecase \"Login\" as UC1\n  usecase \"Manage\" as UC2\n}\nu --&gt; UC1\nUC2 ..&gt; UC1 : &lt;&lt;include&gt;&gt;\n@enduml"),
        ("Component", "@startuml\npackage \"Frontend\" {\n  [Web App] as web\n}\npackage \"Backend\" {\n  [API] as api\n  database \"DB\" as db\n}\nweb --&gt; api\napi --&gt; db\n@enduml"),
        ("Deployment", "@startuml\nnode \"Web Server\" as web {\n  artifact app.war\n}\ndatabase \"PostgreSQL\" as db\nweb --&gt; db : JDBC\n@enduml"),
        ("Entity Relationship", "@startuml\nhide circle\nskinparam linetype ortho\nentity User {\n  *id : number &lt;&lt;PK&gt;&gt;\n  --\n  name : text\n}\nentity Order {\n  *id : number &lt;&lt;PK&gt;&gt;\n  *user_id : number &lt;&lt;FK&gt;&gt;\n}\nUser ||--o{ Order : places\n@enduml"),
        ("Object", "@startuml\nobject Account\nobject User {\n  name = \"Alice\"\n  age = 30\n}\nUser --&gt; Account : owns\n@enduml"),
        ("Gantt", "@startgantt\nProject starts 2024-01-01\n[Design] lasts 10 days\n[Build] lasts 15 days\n[Build] starts after [Design]'s end\n[Build] is 40% completed\n@endgantt"),
        ("JSON", "@startjson\n{\n  \"name\": \"PlantUML\",\n  \"tags\": [\"json\", \"yaml\"],\n  \"owner\": { \"id\": 42 }\n}\n@endjson"),
        ("Mindmap", "@startmindmap\n* Root\n** Branch A\n*** Leaf A1\n** Branch B\n@endmindmap"),
        ("Salt (wireframe)", "@startsalt\n{\n  Login    | \"MyName  \"\n  Password | \"****    \"\n  [Cancel] | [  OK  ]\n}\n@endsalt"),
        ("Preprocessor", "@startuml\n!function $double($x)\n  !return $x * 2\n!endfunction\nAlice -&gt; Bob : %intval($double(2))\n@enduml"),
        ("Styled (skinparam/theme)", "@startuml\n!theme plain\nskinparam backgroundColor #FEFEFE\nskinparam shadowing false\nskinparam roundCorner 10\nclass Foo\nclass Bar\nFoo --&gt; Bar\n@enduml"),
    ]
}
