import XCTest
@testable import MindoScript
import MindoModel

final class AgentToolsTopicExtrasTests: XCTestCase {

    /// Espresso/Equipment(Grinder, Machine)/Beans tree.
    private func sampleMap() -> MindMap {
        let root = Topic(text: "Espresso")
        let eq = root.addChild(text: "Equipment")
        _ = eq.addChild(text: "Grinder")
        _ = eq.addChild(text: "Machine")
        _ = root.addChild(text: "Beans")
        return MindMap(root: root)
    }

    private func tools(_ map: MindMap, effects: AgentToolEffects = AgentToolEffects()) -> MindoAgentTools {
        MindoAgentTools(map: map, effects: effects)
    }

    // MARK: - set_topic_note

    func testSetTopicNoteByQuery() {
        let map = sampleMap()
        let fx = AgentToolEffects()
        let r = tools(map, effects: fx).handle(name: "set_topic_note",
                                               argumentsJSON: #"{"query":"Grinder","text":"Use burr"}"#)
        XCTAssertEqual(r, "set note on \"Grinder\"")
        XCTAssertTrue(fx.mapMutated)
        let grinder = map.topic(atOutlinePath: "0/0")!
        XCTAssertEqual((grinder.extra(.note) as? ExtraNote)?.text, "Use burr")
    }

    func testSetTopicNoteByPath() {
        let map = sampleMap()
        let r = tools(map).handle(name: "set_topic_note",
                                  argumentsJSON: #"{"path":"1","text":"single origin"}"#)
        XCTAssertEqual(r, "set note on \"Beans\"")
    }

    func testSetTopicNoteReplaces() {
        let map = sampleMap()
        let t = tools(map)
        _ = t.handle(name: "set_topic_note", argumentsJSON: #"{"query":"Beans","text":"first"}"#)
        _ = t.handle(name: "set_topic_note", argumentsJSON: #"{"query":"Beans","text":"second"}"#)
        let beans = map.topic(atOutlinePath: "1")!
        XCTAssertEqual((beans.extra(.note) as? ExtraNote)?.text, "second")
    }

    func testSetTopicNoteMissingText() {
        let r = tools(sampleMap()).handle(name: "set_topic_note", argumentsJSON: #"{"query":"Beans"}"#)
        XCTAssertEqual(r, "error: missing 'text'")
    }

    func testSetTopicNoteNoMatch() {
        let fx = AgentToolEffects()
        let r = tools(sampleMap(), effects: fx).handle(name: "set_topic_note",
                                                       argumentsJSON: #"{"query":"Nope","text":"x"}"#)
        XCTAssertEqual(r, "error: no topic matches the given path/query")
        XCTAssertFalse(fx.mapMutated)
    }

    // MARK: - get_topic_note

    func testGetTopicNote() {
        let map = sampleMap()
        let t = tools(map)
        _ = t.handle(name: "set_topic_note", argumentsJSON: #"{"query":"Grinder","text":"hello note"}"#)
        let r = t.handle(name: "get_topic_note", argumentsJSON: #"{"query":"Grinder"}"#)
        XCTAssertEqual(r, "hello note")
    }

    func testGetTopicNoteNone() {
        let r = tools(sampleMap()).handle(name: "get_topic_note", argumentsJSON: #"{"query":"Beans"}"#)
        XCTAssertEqual(r, "(no note)")
    }

    func testGetTopicNoteNoMatch() {
        let r = tools(sampleMap()).handle(name: "get_topic_note", argumentsJSON: #"{"query":"Nope"}"#)
        XCTAssertEqual(r, "error: no topic matches the given path/query")
    }

    // MARK: - link_topics

    func testLinkTopicsByQuery() {
        let map = sampleMap()
        let fx = AgentToolEffects()
        let r = tools(map, effects: fx).handle(name: "link_topics",
                                               argumentsJSON: #"{"from":"Grinder","to":"Beans"}"#)
        XCTAssertEqual(r, "linked \"Grinder\" → \"Beans\"")
        XCTAssertTrue(fx.mapMutated)
        let grinder = map.topic(atOutlinePath: "0/0")!
        let beans = map.topic(atOutlinePath: "1")!
        let uid = beans.attribute(ExtraTopic.topicUidAttr)
        XCTAssertNotNil(uid)
        XCTAssertEqual((grinder.extra(.topic) as? ExtraTopic)?.topicUID, uid)
        // UID lets the map resolve the target back.
        XCTAssertTrue(map.findTopic(uid: uid!) === beans)
    }

    func testLinkTopicsByPath() {
        let map = sampleMap()
        let r = tools(map).handle(name: "link_topics",
                                  argumentsJSON: #"{"from_path":"0/1","to_path":"0/0"}"#)
        XCTAssertEqual(r, "linked \"Machine\" → \"Grinder\"")
    }

    func testLinkTopicsReusesExistingUID() {
        let map = sampleMap()
        let beans = map.topic(atOutlinePath: "1")!
        beans.setAttribute(ExtraTopic.topicUidAttr, "fixed-uid")
        _ = tools(map).handle(name: "link_topics", argumentsJSON: #"{"from":"Grinder","to":"Beans"}"#)
        XCTAssertEqual(beans.attribute(ExtraTopic.topicUidAttr), "fixed-uid")
        let grinder = map.topic(atOutlinePath: "0/0")!
        XCTAssertEqual((grinder.extra(.topic) as? ExtraTopic)?.topicUID, "fixed-uid")
    }

    func testLinkTopicsSameTopic() {
        let fx = AgentToolEffects()
        let r = tools(sampleMap(), effects: fx).handle(name: "link_topics",
                                                       argumentsJSON: #"{"from":"Beans","to":"Beans"}"#)
        XCTAssertEqual(r, "error: source and target are the same topic")
        XCTAssertFalse(fx.mapMutated)
    }

    func testLinkTopicsMissingSource() {
        let r = tools(sampleMap()).handle(name: "link_topics", argumentsJSON: #"{"to":"Beans"}"#)
        XCTAssertEqual(r, "error: no topic matches the given from_path/from")
    }

    func testLinkTopicsMissingTarget() {
        let r = tools(sampleMap()).handle(name: "link_topics", argumentsJSON: #"{"from":"Beans"}"#)
        XCTAssertEqual(r, "error: no topic matches the given to_path/to")
    }

    // MARK: - set_topic_collapsed

    func testSetCollapsedTrue() {
        let map = sampleMap()
        let fx = AgentToolEffects()
        let r = tools(map, effects: fx).handle(name: "set_topic_collapsed",
                                               argumentsJSON: #"{"query":"Equipment","collapsed":true}"#)
        XCTAssertEqual(r, "set collapsed=true on \"Equipment\"")
        XCTAssertTrue(fx.mapMutated)
        XCTAssertEqual(map.topic(atOutlinePath: "0")!.attribute("collapsed"), "true")
    }

    func testSetCollapsedFalseClears() {
        let map = sampleMap()
        let eq = map.topic(atOutlinePath: "0")!
        eq.setAttribute("collapsed", "true")
        let r = tools(map).handle(name: "set_topic_collapsed",
                                  argumentsJSON: #"{"path":"0","collapsed":false}"#)
        XCTAssertEqual(r, "set collapsed=false on \"Equipment\"")
        XCTAssertNil(eq.attribute("collapsed"))
    }

    func testSetCollapsedMissingArg() {
        let r = tools(sampleMap()).handle(name: "set_topic_collapsed", argumentsJSON: #"{"query":"Equipment"}"#)
        XCTAssertEqual(r, "error: missing 'collapsed'")
    }

    func testSetCollapsedNoMatch() {
        let r = tools(sampleMap()).handle(name: "set_topic_collapsed",
                                          argumentsJSON: #"{"query":"Nope","collapsed":true}"#)
        XCTAssertEqual(r, "error: no topic matches the given path/query")
    }

    // MARK: - dispatch

    func testUnknownToolNotHandled() {
        let t = tools(sampleMap())
        XCTAssertNil(t.handleTopicExtras("not_a_tool", ToolArgs([:])))
    }

    func testDescriptorsAreValidJSON() {
        for d in MindoAgentTools.topicExtrasDescriptors {
            let obj = try? JSONSerialization.jsonObject(with: Data(d.parametersJSON.utf8))
            XCTAssertNotNil(obj, "invalid JSON for \(d.name)")
        }
        XCTAssertEqual(MindoAgentTools.topicExtrasDescriptors.count, 4)
    }
}
