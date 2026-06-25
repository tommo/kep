import XCTest
@testable import KepModel

final class NovamindImporterTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("NovamindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        if let dir, FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private func makeNm5(_ contentXML: String) throws -> Data {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "no /usr/bin/zip")
        try contentXML.write(to: dir.appendingPathComponent("content.xml"), atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-q", "doc.nm5", "content.xml"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        try XCTSkipUnless(p.terminationStatus == 0, "zip failed")
        return try Data(contentsOf: dir.appendingPathComponent("doc.nm5"))
    }

    private let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <document>
      <topics>
        <topic id="c0"><rich-text><text-run>Root Idea</text-run></rich-text></topic>
        <topic id="c1">
          <rich-text><text-run>Branch<br/>two lines</text-run></rich-text>
          <notes><rich-text><text-run>a note</text-run></rich-text></notes>
        </topic>
        <topic id="c2"><rich-text><text-run>Leaf</text-run></rich-text></topic>
      </topics>
      <maps>
        <map>
          <topic-node id="n0" topic-ref="c0">
            <sub-topics>
              <topic-node id="n1" topic-ref="c1">
                <sub-topics>
                  <topic-node id="n2" topic-ref="c2"/>
                </sub-topics>
              </topic-node>
            </sub-topics>
          </topic-node>
        </map>
      </maps>
    </document>
    """

    func testImportsTreeTextAndNotes() throws {
        let map = try NovamindImporter.parse(data: makeNm5(sample))
        XCTAssertEqual(map.root?.text, "Root Idea")
        XCTAssertEqual(map.root?.children.map(\.text), ["Branch\ntwo lines"])   // <br/> → newline
        let branch = map.root?.children.first
        XCTAssertEqual((branch?.extra(.note) as? ExtraNote)?.text, "a note")
        XCTAssertEqual(branch?.children.map(\.text), ["Leaf"])
    }

    func testImportsColorsAndJumpLinks() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <document>
          <topics>
            <topic id="c0"><rich-text><text-run>Root</text-run></rich-text></topic>
            <topic id="c1"><rich-text><text-run>A</text-run></rich-text></topic>
            <topic id="c2"><rich-text><text-run>B</text-run></rich-text></topic>
          </topics>
          <maps>
            <map>
              <topic-node id="n0" topic-ref="c0">
                <sub-topics>
                  <topic-node id="n1" topic-ref="c1">
                    <topic-node-view><topic-node-style>
                      <fill-style><solid-color color="#FFCCDD"/></fill-style>
                      <line-style color="#112233"/>
                    </topic-node-style></topic-node-view>
                  </topic-node>
                  <topic-node id="n2" topic-ref="c2"/>
                </sub-topics>
              </topic-node>
              <link-lines>
                <topic-node>
                  <link-line-data start-topic-node-ref="n1" end-topic-node-ref="n2"/>
                </topic-node>
              </link-lines>
            </map>
          </maps>
        </document>
        """
        let map = try NovamindImporter.parse(data: makeNm5(xml))
        let a = try XCTUnwrap(map.root?.children.first { $0.text == "A" })
        let b = try XCTUnwrap(map.root?.children.first { $0.text == "B" })
        XCTAssertEqual(a.attribute(TopicAttribute.fillColor), "#FFCCDD")
        XCTAssertEqual(a.attribute(TopicAttribute.borderColor), "#112233")
        // Jump-link A → B: B gains a UID, A's ExtraTopic points to it.
        let uid = try XCTUnwrap(b.attribute(ExtraTopic.topicUidAttr))
        XCTAssertEqual((a.extra(.topic) as? ExtraTopic)?.topicUID, uid)
    }

    func testRootFallbackWhenNoText() throws {
        let xml = """
        <document><topics></topics>
          <maps><map><topic-node id="n0"/></map></maps>
        </document>
        """
        XCTAssertEqual(try NovamindImporter.parse(data: makeNm5(xml)).root?.text, "Novamind Map")
    }

    func testNonZipThrows() {
        XCTAssertThrowsError(try NovamindImporter.parse(data: Data("nope".utf8)))
    }

    func testZipWithoutContentThrows() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "no /usr/bin/zip")
        try "x".write(to: dir.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-q", "empty.nm5", "other.txt"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        let data = try Data(contentsOf: dir.appendingPathComponent("empty.nm5"))
        XCTAssertThrowsError(try NovamindImporter.parse(data: data))
    }
}
