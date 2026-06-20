import Foundation

/// A starter scaffold for a new PlantUML document. Mindo's port of javamind's
/// `PlantUmlTemplates` (a flat `Arrays.asList` of 19 diagram skeletons). The
/// bodies are cleaned of the Java app's attribution comment / footer; each is a
/// self-contained, renderable diagram the user can edit in place.
public struct PlantUMLTemplate: Identifiable, Hashable, Sendable {
    /// Stable kebab-case identifier (also the picker selection key).
    public let id: String
    /// Display name shown in the template picker.
    public let name: String
    /// A coarse grouping for the picker; purely cosmetic.
    public let category: String
    /// The full PlantUML source, including the `@startX … @endX` fence.
    public let body: String

    public init(id: String, name: String, category: String, body: String) {
        self.id = id
        self.name = name
        self.category = category
        self.body = body
    }
}

/// The built-in PlantUML document templates, in picker order. "Blank" is first
/// so the default selection is the lightest scaffold.
public enum PlantUMLTemplates {

    public static let all: [PlantUMLTemplate] = [
        // MARK: Common
        PlantUMLTemplate(id: "blank", name: "Blank", category: "Common", body: """
        @startuml
        title Untitled

        @enduml
        """),
        PlantUMLTemplate(id: "sequence", name: "Sequence", category: "Common", body: """
        @startuml
        title Sequence

        Alice -> Bob: Authentication Request
        Bob --> Alice: Authentication Response

        Alice -> Bob: Another authentication Request
        Alice <-- Bob: Another authentication Response
        @enduml
        """),
        PlantUMLTemplate(id: "class", name: "Class", category: "Common", body: """
        @startuml
        title Class

        Object <|-- ArrayList
        Object : equals()
        ArrayList : Object[] elementData
        ArrayList : size()
        @enduml
        """),
        PlantUMLTemplate(id: "activity", name: "Activity", category: "Common", body: """
        @startuml
        title Activity

        start
        :Hello world;
        :This is defined on
        several **lines**;
        end
        @enduml
        """),
        PlantUMLTemplate(id: "use-case", name: "Use Case", category: "Common", body: """
        @startuml
        title Use Case

        User -> (Start)
        User --> (Use the application) : A small label
        :Main Admin: ---> (Use the application) : This is\\nyet another\\nlabel
        @enduml
        """),
        PlantUMLTemplate(id: "state", name: "State", category: "Common", body: """
        @startuml
        title State

        [*] --> State1
        State1 --> [*]
        State1 : this is a string
        State1 : this is another string

        State1 --> State2
        State2 --> [*]
        @enduml
        """),

        // MARK: Structure
        PlantUMLTemplate(id: "component", name: "Component", category: "Structure", body: """
        @startuml
        title Component

        DataAccess - [First Component]
        [First Component] ..> HTTP : use
        @enduml
        """),
        PlantUMLTemplate(id: "deployment", name: "Deployment", category: "Structure", body: """
        @startuml
        title Deployment

        node Node1 as n1
        node "Node 2" as n2
        file f1 as "File 1"
        cloud c1 as "this
        is
        a
        cloud"

        n1 -> n2
        n1 --> f1
        f1 -> c1
        @enduml
        """),
        PlantUMLTemplate(id: "object", name: "Object", category: "Structure", body: """
        @startuml
        title Object

        object London
        object Washington
        object Berlin

        map CapitalCity {
          UK *-> London
          USA *--> Washington
          Germany *---> Berlin
        }
        @enduml
        """),
        PlantUMLTemplate(id: "network", name: "Network", category: "Structure", body: """
        @startuml
        title Network

        nwdiag {
          network dmz {
            address = "210.x.x.x/24"

            web01 [address = "210.x.x.1"];
            web02 [address = "210.x.x.2"];
          }
          network internal {
            address = "172.x.x.x/24";

            web01 [address = "172.x.x.1"];
            db01;
          }
        }
        @enduml
        """),
        PlantUMLTemplate(id: "entity-relationship", name: "Entity Relationship", category: "Structure", body: """
        @startuml
        title Entity Relationship

        hide circle
        skinparam linetype ortho

        entity "Entity01" as e01 {
          *id : number <<generated>>
          --
          *name : varchar
          description : varchar
        }

        entity "Entity02" as e02 {
          *id : number <<generated>>
          --
          *e1_id : number <<FK>>
          other_details : varchar
        }

        e01 ||..o{ e02
        @enduml
        """),
        PlantUMLTemplate(id: "archimate", name: "Archimate", category: "Structure", body: """
        @startuml
        title Archimate

        archimate #Technology "VPN Server" as vpnServerA <<technology-device>>

        rectangle GO #lightgreen
        rectangle STOP #red
        rectangle WAIT #orange
        @enduml
        """),

        // MARK: Planning
        PlantUMLTemplate(id: "gantt", name: "Gantt", category: "Planning", body: """
        @startgantt
        title Gantt

        Project starts 2020-07-01
        [Test prototype] lasts 10 days
        [Prototype completed] happens 2020-07-10
        [Setup assembly line] lasts 12 days
        [Setup assembly line] starts at [Test prototype]'s end
        @endgantt
        """),
        PlantUMLTemplate(id: "wbs", name: "Work Breakdown", category: "Planning", body: """
        @startwbs
        title Work Breakdown

        * Business Process Modelling WBS
        ** Launch the project
        *** Complete Stakeholder Research
        *** Initial Implementation Plan
        ** Design phase
        *** Model of AsIs Processes Completed
        ***< Measure AsIs performance metrics
        ***< Identify Quick Wins
        @endwbs
        """),
        PlantUMLTemplate(id: "wireframe", name: "Wireframe", category: "Planning", body: """
        @startsalt
        title Wireframe

        {
          Just plain text
          [This is my button]
          ()  Unchecked radio
          (X) Checked radio
          []  Unchecked box
          [X] Checked box
          "Enter text here   "
          ^This is a droplist^
        }
        @endsalt
        """),

        // MARK: Data & Notation
        PlantUMLTemplate(id: "json", name: "JSON", category: "Data & Notation", body: """
        @startjson
        {
          "name": "JSON",
          "content": {
            "title": "This is a JSON script"
          }
        }
        @endjson
        """),
        PlantUMLTemplate(id: "yaml", name: "YAML", category: "Data & Notation", body: """
        @startyaml
        name: YAML
        content:
          title: This is a YAML script
        @endyaml
        """),
        PlantUMLTemplate(id: "ebnf", name: "EBNF", category: "Data & Notation", body: """
        @startebnf
        title Title
        my_enbf = {"a", c , "a" (* Note on a *)}
        | ? special ?
        | "repetition", 4 * '2';
        (* Global End Note *)
        @endebnf
        """),
        PlantUMLTemplate(id: "regex", name: "Regex", category: "Data & Notation", body: """
        @startregex
        title minimumRepetition
        ab{1}c{1,}
        @endregex
        """),
    ]

    /// The default scaffold for a brand-new `.puml` (the blank one).
    public static var blank: PlantUMLTemplate { all[0] }

    /// Look up a template by its stable id.
    public static func template(id: String) -> PlantUMLTemplate? {
        all.first { $0.id == id }
    }

    /// Templates grouped by `category`, preserving first-seen category order.
    public static var grouped: [(category: String, templates: [PlantUMLTemplate])] {
        var order: [String] = []
        var buckets: [String: [PlantUMLTemplate]] = [:]
        for t in all {
            if buckets[t.category] == nil { order.append(t.category) }
            buckets[t.category, default: []].append(t)
        }
        return order.map { ($0, buckets[$0]!) }
    }
}
