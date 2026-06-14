import XCTest
@testable import MindoCore

final class PreviewContextMenuTests: XCTestCase {

    func testPlantUMLMenuHasAllFourActions() {
        let items = PreviewContextMenu.plantUML(hasRenderedDiagram: true)
        XCTAssertEqual(items.map { $0.action },
                       [.refresh, .copySVG, .copyPNG, .export])
    }

    func testPlantUMLRefreshAlwaysEnabled() {
        for rendered in [true, false] {
            let refresh = PreviewContextMenu.plantUML(hasRenderedDiagram: rendered)
                .first { $0.action == .refresh }
            XCTAssertEqual(refresh?.isEnabled, true)
        }
    }

    func testPlantUMLCopyExportDisabledUntilRendered() {
        let none = PreviewContextMenu.plantUML(hasRenderedDiagram: false)
        for action in [PreviewMenuAction.copySVG, .copyPNG, .export] {
            XCTAssertEqual(none.first { $0.action == action }?.isEnabled, false,
                           "\(action) should be disabled before a render")
        }
    }

    func testPlantUMLCopyExportEnabledOnceRendered() {
        let some = PreviewContextMenu.plantUML(hasRenderedDiagram: true)
        for action in [PreviewMenuAction.copySVG, .copyPNG, .export] {
            XCTAssertEqual(some.first { $0.action == action }?.isEnabled, true)
        }
    }

    func testMarkdownMenuItems() {
        let items = PreviewContextMenu.markdown()
        XCTAssertEqual(items.map { $0.action }, [.refresh, .viewSource])
        XCTAssertTrue(items.allSatisfy { $0.isEnabled })
    }

    func testEveryItemHasANonEmptyTitle() {
        let all = PreviewContextMenu.plantUML(hasRenderedDiagram: true) + PreviewContextMenu.markdown()
        XCTAssertTrue(all.allSatisfy { !$0.title.isEmpty })
    }
}
