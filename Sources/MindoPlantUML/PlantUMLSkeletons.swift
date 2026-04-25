import Foundation

/// Bundled diagram skeletons surfaced by the PlantUML editor toolbar.
/// Mirrors the small subset of mindolph-plantuml's SnippetGroup library
/// that covers the diagram types most users start from.
public enum PlantUMLSkeletons {

    public static let sequence = """
    @startuml
    actor User
    participant App
    participant API

    User -> App: Action
    App -> API: Request
    API --> App: Response
    App --> User: Update
    @enduml
    """

    public static let classDiagram = """
    @startuml
    class Animal {
      +name: String
      +makeSound()
    }
    class Dog {
      +breed: String
    }
    Animal <|-- Dog
    @enduml
    """

    public static let activity = """
    @startuml
    start
    :Read input;
    if (valid?) then (yes)
      :Process;
    else (no)
      :Show error;
      stop
    endif
    :Save;
    stop
    @enduml
    """

    public static let state = """
    @startuml
    [*] --> Idle
    Idle --> Loading : start
    Loading --> Ready : ok
    Loading --> Error : fail
    Ready --> [*]
    Error --> [*]
    @enduml
    """

    public static let useCase = """
    @startuml
    left to right direction
    actor User
    rectangle System {
      User --> (Sign in)
      User --> (Edit profile)
      User --> (Sign out)
    }
    @enduml
    """

    public static let mindMap = """
    @startmindmap
    * Root
    ** Branch A
    *** Leaf A1
    *** Leaf A2
    ** Branch B
    @endmindmap
    """
}
