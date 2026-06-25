import XCTest
import AppKit
@testable import KepBase

final class TextDocumentPrintingTests: XCTestCase {

    /// The bug: ⌘P sent `printDocument:`, an NSDocument method the NSView
    /// responders (NSTextView/WKWebView) don't implement, so nothing in the
    /// chain handled it. These guard that we target `print:` — which they DO
    /// implement — and that the old selector really was unhandled.
    func testPrintSelectorIsPrintColon() {
        XCTAssertEqual(TextDocumentPrinting.printSelector, Selector(("print:")))
    }

    func testTextViewRespondsToPrintSelector() {
        XCTAssertTrue(NSTextView.instancesRespond(to: TextDocumentPrinting.printSelector))
    }

    func testTextViewDoesNotRespondToPrintDocument() {
        XCTAssertFalse(NSTextView.instancesRespond(to: Selector(("printDocument:"))))
    }

    func testWebKitNSViewRespondsToPrintSelector() {
        // WKWebView inherits print: from NSView.
        XCTAssertTrue(NSView.instancesRespond(to: TextDocumentPrinting.printSelector))
    }
}
