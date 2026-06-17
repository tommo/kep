import XCTest
@testable import MindoPlantUML

final class SequenceLayoutTests: XCTestCase {

    /// Deterministic stub: width ∝ char count, fixed line height. No AppKit.
    private let stub = TextMeasurer { s in
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        let widest = lines.map(\.count).max() ?? 0
        return CGSize(width: Double(widest) * 7, height: Double(max(lines.count, 1)) * 16)
    }

    private func layout(_ src: String) -> LayoutResult {
        SequenceLayout.layout(SequenceParser.parse(src), measurer: stub)
    }

    private func actorXs(_ r: LayoutResult) -> [Double] {
        r.ops.compactMap { if case let .actorBox(x, y, w, _, _, _) = $0, y < 60 { return x + w / 2 } else { return nil } }
    }

    // MARK: - Actor positioning

    func testActorXStrictlyIncreasing() {
        let xs = actorXs(layout("@startuml\nA -> B: hi\nB -> C: yo\n@enduml"))
        XCTAssertEqual(xs.count, 3)
        XCTAssertEqual(xs, xs.sorted())
        XCTAssertTrue(zip(xs, xs.dropFirst()).allSatisfy { $1 - $0 > 1 }, "centers must not coincide")
    }

    func testLongLabelWidensGap() {
        let narrow = actorXs(layout("@startuml\nA -> B: hi\n@enduml"))
        let wide = actorXs(layout("@startuml\nA -> B: \(String(repeating: "x", count: 60))\n@enduml"))
        XCTAssertGreaterThan(wide[1] - wide[0], narrow[1] - narrow[0], "a long message label must push B further right")
    }

    func testActorsNonOverlapping() {
        let r = layout("@startuml\nLongNameActor -> B: x\n@enduml")
        let heads = r.ops.compactMap { op -> (Double, Double)? in
            if case let .actorBox(x, y, w, _, _, _) = op, y < 60 { return (x, x + w) } else { return nil }
        }
        for (a, b) in zip(heads, heads.dropFirst()) {
            XCTAssertLessThanOrEqual(a.1, b.0, "head boxes must not overlap horizontally")
        }
    }

    // MARK: - Groups (bounds stack)

    func testAltRectEnclosesChildren() {
        let r = layout("""
        @startuml
        alt ok
          A -> B: x
        else no
          A -> B: y
        end
        @enduml
        """)
        guard let frame = r.ops.first(where: { if case .groupFrame = $0 { return true }; return false }),
              case let .groupFrame(fx, fy, fw, fh, kind, _, _) = frame else { return XCTFail("no frame") }
        XCTAssertEqual(kind, "alt")
        let msgs = r.ops.compactMap { op -> (Double, Double, Double)? in
            if case let .message(from, to, y, _, _, _, _) = op { return (from, to, y) } else { return nil }
        }
        XCTAssertEqual(msgs.count, 2)
        for (mfrom, mto, my) in msgs {
            XCTAssertGreaterThan(my, fy, "message y inside frame top")
            XCTAssertLessThan(my, fy + fh, "message y inside frame bottom")
            XCTAssertLessThanOrEqual(fx, min(mfrom, mto), "frame spans left of message")
            XCTAssertGreaterThanOrEqual(fx + fw, max(mfrom, mto), "frame spans right of message")
        }
    }

    func testNestedContainment() {
        let r = layout("""
        @startuml
        loop 3 times
          alt ok
            A -> B: x
          end
        end
        @enduml
        """)
        let frames = r.ops.compactMap { op -> (Double, Double, String)? in
            if case let .groupFrame(_, y, _, h, kind, _, _) = op { return (y, y + h, kind) } else { return nil }
        }
        XCTAssertEqual(frames.count, 2)
        let outer = frames.first { $0.2 == "loop" }!
        let inner = frames.first { $0.2 == "alt" }!
        XCTAssertLessThanOrEqual(outer.0, inner.0, "loop starts above alt")
        XCTAssertGreaterThanOrEqual(outer.1, inner.1, "loop ends below alt")
    }

    // MARK: - Self message & note

    func testSelfMessageOp() {
        let r = layout("@startuml\nA -> A: think\n@enduml")
        XCTAssertTrue(r.ops.contains { if case .selfMessage = $0 { return true }; return false })
    }

    func testNoteOverTwoActorsSpans() {
        let r = layout("@startuml\nA -> B: hi\nnote over A,B: shared\n@enduml")
        guard let note = r.ops.first(where: { if case .note = $0 { return true }; return false }),
              case let .note(nx, _, nw, _, _) = note else { return XCTFail("no note") }
        let xs = actorXs(r)
        XCTAssertLessThan(nx, xs[0], "note left edge reaches past A")
        XCTAssertGreaterThan(nx + nw, xs[1], "note right edge reaches past B")
    }

    // MARK: - Size & overall sanity

    func testNonEmptyHasPositiveSize() {
        let r = layout("@startuml\nA -> B: hi\n@enduml")
        XCTAssertGreaterThan(r.width, 0)
        XCTAssertGreaterThan(r.height, 0)
        // lifelines reach from head bottom to foot.
        XCTAssertTrue(r.ops.contains { if case .lifeline = $0 { return true }; return false })
        // head + foot box per actor.
        let boxes = r.ops.filter { if case .actorBox = $0 { return true }; return false }
        XCTAssertEqual(boxes.count, 4)
    }

    func testEmptyDiagram() {
        let r = SequenceLayout.layout(SequenceParser.parse("@startuml\n@enduml"), measurer: stub)
        XCTAssertEqual(r.ops.count, 0)
        XCTAssertEqual(r.width, 0)
    }
}
