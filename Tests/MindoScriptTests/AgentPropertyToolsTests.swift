import XCTest
@testable import MindoScript
import MindoModel

final class AgentPropertyToolsTests: XCTestCase {
    private func tools(_ map: MindMap, _ fx: AgentToolEffects = AgentToolEffects()) -> MindoAgentTools {
        MindoAgentTools(map: map, effects: fx)
    }
    private func map() -> MindMap {
        let root = Topic(text: "Tasks")
        root.addChild(text: "A").setProperty("priority", .number(1))
        let b = root.addChild(text: "B"); b.setProperty("priority", .number(1)); b.setProperty("done", .checkbox(true))
        root.addChild(text: "C").setProperty("tags", .list(["urgent", "ui"]))
        return MindMap(root: root)
    }

    func testSetTopicPropertyInfersType() {
        let m = map(); let fx = AgentToolEffects()
        let r = tools(m, fx).handle(name: "set_topic_property",
                                    argumentsJSON: #"{"path":"0","key":"done","value":"true"}"#)
        XCTAssertTrue(r.contains("set property done=true"))
        XCTAssertTrue(fx.mapMutated)
        XCTAssertEqual(m.topic(atOutlinePath: "0")?.property("done"), .checkbox(true))
    }

    func testSetTopicPropertyRejectsReservedKey() {
        let r = tools(map()).handle(name: "set_topic_property",
                                    argumentsJSON: #"{"query":"A","key":"fillColor","value":"x"}"#)
        XCTAssertTrue(r.contains("reserved"), "reserved keys must be refused: \(r)")
    }

    func testFindByPropertyValue() {
        let r = tools(map()).handle(name: "find_topics_by_property",
                                    argumentsJSON: #"{"key":"priority","value":"1"}"#)
        XCTAssertTrue(r.contains("A"), r)
        XCTAssertTrue(r.contains("B"), r)
        XCTAssertFalse(r.contains("] C"), r)
    }

    func testFindByPropertyPresenceAndTagMembership() {
        let m = map()
        XCTAssertTrue(tools(m).handle(name: "find_topics_by_property",
                                      argumentsJSON: #"{"key":"done"}"#).contains("B"))
        XCTAssertTrue(tools(m).handle(name: "find_topics_by_property",
                                      argumentsJSON: #"{"key":"tags","value":"urgent"}"#).contains("C"))
        XCTAssertEqual(tools(m).handle(name: "find_topics_by_property",
                                       argumentsJSON: #"{"key":"missing"}"#), "(none)")
    }
}
