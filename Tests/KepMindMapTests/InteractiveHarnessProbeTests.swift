import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// Probe: can we drive a REAL window + responder chain + field editor in a
/// headless test? If these pass, we can build genuine interactive tests that
/// exercise the actual NSEvent dispatch and NSTextField field editor (which
/// the window-less unit tests cannot — currentEditor() is nil with no window).
@MainActor
final class InteractiveHarnessProbeTests: XCTestCase {

    func testWindowMakesTextFieldEditorLive() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 200, height: 24))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        let became = window.makeFirstResponder(field)
        XCTAssertTrue(became, "field should accept first responder")
        let editor = field.currentEditor()
        try XCTSkipIf(editor == nil, "no field editor in this headless environment — windowed UI tests unavailable")
        XCTAssertNotNil(editor)
    }

    func testSendEventTypesIntoFieldEditor() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 200, height: 24))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(field)
        try XCTSkipIf(field.currentEditor() == nil, "no field editor — skip")

        let ev = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "Z", charactersIgnoringModifiers: "Z",
            isARepeat: false, keyCode: 0)!
        window.sendEvent(ev)
        XCTAssertEqual(field.stringValue, "Z", "a real key event typed into the field editor")
    }
}
