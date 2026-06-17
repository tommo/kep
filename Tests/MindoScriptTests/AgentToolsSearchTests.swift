import XCTest
import MindoModel
import MindoCore
@testable import MindoScript

final class AgentToolsSearchTests: XCTestCase {

    private let files = [
        URL(fileURLWithPath: "/ws/Architecture.md"),
        URL(fileURLWithPath: "/ws/Auth.md"),
        URL(fileURLWithPath: "/ws/Notes.txt"),
    ]

    private func corpus() -> [(url: URL, text: String)] {
        [
            (files[0], """
            # Overview
            The system is layered.
            ## Auth Layer
            Handles login and tokens.
            Uses sessions.
            ## Data Layer
            Stores records.
            # Appendix
            Misc notes.
            """),
            (files[1], "Auth links to [[Architecture]] and [[Architecture#Auth Layer]].\nAlso [[Notes]] and [[Missing Doc]]."),
            (files[2], "plain text file\nTODO: cleanup\nThe END"),
        ]
    }

    private func tools() -> MindoAgentTools {
        MindoAgentTools(map: MindMap(root: Topic(text: "R")), corpus: corpus(), allFiles: files)
    }

    private func call(_ name: String, _ json: String) -> String {
        tools().handle(name: name, argumentsJSON: json)
    }

    // MARK: search_workspace

    func testSearchSubstringCaseInsensitive() {
        let r = call("search_workspace", #"{"query":"auth"}"#)
        XCTAssertTrue(r.contains("Architecture:3: ## Auth Layer"), r)
        XCTAssertTrue(r.contains("Auth:1:"), r)
    }

    func testSearchNoMatches() {
        XCTAssertEqual(call("search_workspace", #"{"query":"zzzzznope"}"#), "(no matches)")
    }

    func testSearchFileTypeFilter() {
        let r = call("search_workspace", #"{"query":"the","file_type":"txt"}"#)
        // Only Notes.txt should match (Architecture is .md).
        XCTAssertTrue(r.contains("Notes:3: The END"), r)
        XCTAssertFalse(r.contains("Architecture:"), r)
    }

    func testSearchMaxHits() {
        let r = call("search_workspace", #"{"query":"a","max_hits":2}"#)
        XCTAssertEqual(r.components(separatedBy: "\n").count, 2)
    }

    func testSearchRegex() {
        let r = call("search_workspace", #"{"query":"^##\\s+\\w+","regex":true}"#)
        XCTAssertTrue(r.contains("## Auth Layer"), r)
        XCTAssertTrue(r.contains("## Data Layer"), r)
        XCTAssertFalse(r.contains("# Overview"), r)
    }

    func testSearchInvalidRegex() {
        XCTAssertEqual(call("search_workspace", #"{"query":"[unclosed","regex":true}"#), "error: invalid regex")
    }

    func testSearchMissingQuery() {
        XCTAssertEqual(call("search_workspace", "{}"), "error: missing 'query'")
    }

    // MARK: document_outline

    func testDocumentOutline() {
        let r = call("document_outline", #"{"name":"Architecture"}"#)
        let expected = "Overview\n  Auth Layer\n  Data Layer\nAppendix"
        XCTAssertEqual(r, expected)
    }

    func testDocumentOutlineNoHeadings() {
        XCTAssertEqual(call("document_outline", #"{"name":"Notes"}"#), "(no headings)")
    }

    func testDocumentOutlineNotFound() {
        XCTAssertEqual(call("document_outline", #"{"name":"Ghost"}"#), "not found")
    }

    func testDocumentOutlineMissingName() {
        XCTAssertEqual(call("document_outline", "{}"), "error: missing 'name'")
    }

    // MARK: read_section

    func testReadSection() {
        let r = call("read_section", #"{"name":"Architecture","heading":"Auth"}"#)
        XCTAssertEqual(r, "Handles login and tokens.\nUses sessions.")
    }

    func testReadSectionStopsAtSameOrHigherLevel() {
        // Overview is level 1; its body includes the deeper ## subsections and
        // stops only at the next level-1 heading ("# Appendix").
        let r = call("read_section", #"{"name":"Architecture","heading":"Overview"}"#)
        let expected = """
        The system is layered.
        ## Auth Layer
        Handles login and tokens.
        Uses sessions.
        ## Data Layer
        Stores records.
        """
        XCTAssertEqual(r, expected)
    }

    func testReadSectionNotFound() {
        XCTAssertEqual(call("read_section", #"{"name":"Architecture","heading":"Nonexistent"}"#), "not found")
    }

    func testReadSectionDocNotFound() {
        XCTAssertEqual(call("read_section", #"{"name":"Ghost","heading":"X"}"#), "not found")
    }

    func testReadSectionMissingArgs() {
        XCTAssertEqual(call("read_section", #"{"name":"Architecture"}"#), "error: missing 'heading'")
        XCTAssertEqual(call("read_section", #"{"heading":"Auth"}"#), "error: missing 'name'")
    }

    // MARK: outgoing_links

    func testOutgoingLinksDistinctResolved() {
        // Auth.md links to Architecture (twice) + Notes + Missing Doc (unresolvable).
        let r = call("outgoing_links", #"{"name":"Auth"}"#)
        XCTAssertEqual(r, "Architecture, Notes")
    }

    func testOutgoingLinksNone() {
        XCTAssertEqual(call("outgoing_links", #"{"name":"Notes"}"#), "(none)")
    }

    func testOutgoingLinksDocNotFound() {
        XCTAssertEqual(call("outgoing_links", #"{"name":"Ghost"}"#), "not found")
    }

    func testOutgoingLinksMissingName() {
        XCTAssertEqual(call("outgoing_links", "{}"), "error: missing 'name'")
    }

    // MARK: semantic_search

    func testSemanticSearchMissingQuery() {
        XCTAssertEqual(call("semantic_search", "{}"), "error: missing 'query'")
    }

    func testSemanticSearchRanksRelevantDoc() throws {
        try XCTSkipUnless(NLTextEmbedder().isAvailable, "No NL sentence-embedding model on this host")
        let r = call("semantic_search", #"{"query":"how are user logins and tokens handled","k":2}"#)
        XCTAssertFalse(r.hasPrefix("error:"), r)
        XCTAssertFalse(r.hasPrefix("("), r)         // not "(no matches)"
        // The Auth-Layer passage in Architecture.md should surface.
        XCTAssertTrue(r.contains("Architecture") || r.contains("Auth"), r)
    }

    // MARK: handler ownership

    func testHandlerReturnsNilForForeignTool() {
        XCTAssertNil(tools().handleSearch("not_a_search_tool", ToolArgs([:])))
    }
}
