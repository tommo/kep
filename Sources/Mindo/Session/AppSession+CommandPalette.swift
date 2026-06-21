import Foundation
import MindoCore
import MindoMarkdown

extension AppSession {

    /// Apply a markdown formatting command to the focused markdown editor
    /// (no-op when a markdown editor isn't focused).
    @MainActor
    func applyMarkdownFormat(_ command: MarkdownFormatBridge.Command) {
        MarkdownFormatBridge.perform(command)
    }

    /// The catalog of global actions surfaced in the ⌘⇧P command palette.
    /// Each entry pairs a pure `AppCommand` (id/title/enabled — what the
    /// palette ranks and renders) with the closure that runs it. The
    /// `isEnabled` flags mirror the `.disabled(...)` state of the matching
    /// menu items so the palette can't fire an action the menu wouldn't.
    @MainActor
    func paletteCommands() -> [PaletteCommand] {
        let hasDoc = activeDocument != nil
        let hasWorkspaces = !workspaceRoots.isEmpty
        let isMindMap = activeFileType == .mindMap
        let isMarkdown = activeFileType == .markdown

        func cmd(_ id: String, _ title: String, category: String,
                 shortcut: String? = nil, enabled: Bool = true,
                 _ run: @escaping () -> Void) -> PaletteCommand {
            PaletteCommand(
                command: AppCommand(id: id, title: title, category: category,
                                    shortcut: shortcut, isEnabled: enabled),
                run: run
            )
        }

        return [
            // File
            cmd("file.newMindMap", L("menu.file.new_mindmap"), category: L("palette.cat.file"),
                shortcut: "⌘N") { self.newMindMap() },
            cmd("file.newMarkdown", L("menu.file.new_markdown"), category: L("palette.cat.file"),
                shortcut: "⇧⌘N") { self.newMarkdown() },
            cmd("file.newCSV", L("menu.file.new_csv"), category: L("palette.cat.file")) { self.newCSV() },
            cmd("file.newPlantUML", L("menu.file.new_plantuml"), category: L("palette.cat.file")) { self.newPlantUML() },
            cmd("file.newText", L("menu.file.new_text"), category: L("palette.cat.file")) { self.newTextFile() },
            cmd("file.quickOpen", L("menu.file.quick_open"), category: L("palette.cat.file"),
                shortcut: "⌘O", enabled: hasWorkspaces) { self.quickSwitcherOpen = true },
            cmd("nav.gotoNode", L("menu.file.goto_node"), category: L("palette.cat.navigate"),
                shortcut: "⌘P", enabled: isMindMap) { self.nodeJumpOpen = true },
            cmd("file.openWorkspace", L("menu.file.open_workspace"), category: L("palette.cat.file"),
                shortcut: "⇧⌘O") { self.openWorkspace() },
            cmd("file.openFile", L("menu.file.open_file"), category: L("palette.cat.file"),
                shortcut: "⌥⌘O") { self.openFile() },
            cmd("file.save", L("menu.file.save"), category: L("palette.cat.file"),
                shortcut: "⌘S", enabled: hasDoc) { self.saveActive() },
            cmd("file.saveAs", L("menu.file.save_as"), category: L("palette.cat.file"),
                shortcut: "⇧⌘S", enabled: hasDoc) { self.saveActiveAs() },
            cmd("file.saveAll", L("menu.file.save_all"), category: L("palette.cat.file"),
                shortcut: "⌥⌘S", enabled: hasDirtyOpenDocuments) { self.saveAllDirty() },
            cmd("file.closeTab", L("menu.file.close_tab"), category: L("palette.cat.file"),
                shortcut: "⌘W", enabled: hasDoc) { self.closeActive() },
            cmd("file.print", L("menu.file.print"), category: L("palette.cat.file"),
                enabled: hasDoc) { self.printActiveDocument() },

            // Edit / search
            cmd("edit.find", L("menu.edit.find"), category: L("palette.cat.edit"),
                shortcut: "⌘F", enabled: hasDoc) { self.invokeFindInActiveDocument() },
            cmd("edit.findInFiles", L("menu.edit.find_in_files"), category: L("palette.cat.edit"),
                shortcut: "⇧⌘F", enabled: hasWorkspaces) { self.findInFilesOpen = true },
            cmd("edit.insertSnippet", L("menu.edit.insert_snippet"), category: L("palette.cat.edit"),
                shortcut: "⇧⌘J", enabled: hasDoc) { self.snippetPickerOpen = true },

            // Markdown formatting — operate on the focused markdown editor's
            // selection (palette-first, per the project UX direction).
            cmd("format.heading1", L("menu.format.heading1"), category: L("palette.cat.format"),
                shortcut: "⌥⌘1", enabled: isMarkdown) { self.applyMarkdownFormat(.heading1) },
            cmd("format.heading2", L("menu.format.heading2"), category: L("palette.cat.format"),
                shortcut: "⌥⌘2", enabled: isMarkdown) { self.applyMarkdownFormat(.heading2) },
            cmd("format.heading3", L("menu.format.heading3"), category: L("palette.cat.format"),
                shortcut: "⌥⌘3", enabled: isMarkdown) { self.applyMarkdownFormat(.heading3) },
            cmd("format.quote", L("menu.format.quote"), category: L("palette.cat.format"),
                enabled: isMarkdown) { self.applyMarkdownFormat(.quote) },
            cmd("format.horizontalRule", L("menu.format.hr"), category: L("palette.cat.format"),
                enabled: isMarkdown) { self.applyMarkdownFormat(.horizontalRule) },
            cmd("format.comment", L("menu.format.comment"), category: L("palette.cat.format"),
                enabled: isMarkdown) { self.applyMarkdownFormat(.comment) },
            cmd("format.table", L("menu.format.table"), category: L("palette.cat.format"),
                enabled: isMarkdown) { self.applyMarkdownFormat(.table) },
            cmd("format.image", L("menu.format.image"), category: L("palette.cat.format"),
                enabled: isMarkdown) { self.applyMarkdownFormat(.image) },

            // View
            cmd("view.zoomIn", L("menu.view.zoom_in"), category: L("palette.cat.view"),
                shortcut: "⌘=") { self.zoomCommand = .in; self.zoomCommandTick &+= 1 },
            cmd("view.zoomOut", L("menu.view.zoom_out"), category: L("palette.cat.view"),
                shortcut: "⌘-") { self.zoomCommand = .out; self.zoomCommandTick &+= 1 },
            cmd("view.resetZoom", L("menu.view.reset_zoom"), category: L("palette.cat.view"),
                shortcut: "⌘0") { self.zoomCommand = .reset; self.zoomCommandTick &+= 1 },
            cmd("view.zoomToFit", L("menu.view.zoom_to_fit"), category: L("palette.cat.view"),
                shortcut: "⌘9") { self.zoomCommand = .fit; self.zoomCommandTick &+= 1 },
            cmd("view.foldAll", L("menu.view.fold_all"), category: L("palette.cat.view"),
                enabled: isMindMap) { self.mindmapCommand = .foldAll; self.mindmapCommandTick &+= 1 },
            cmd("view.unfoldAll", L("menu.view.unfold_all"), category: L("palette.cat.view"),
                enabled: isMindMap) { self.mindmapCommand = .unfoldAll; self.mindmapCommandTick &+= 1 },
        ]
    }
}
