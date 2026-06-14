import AppKit
import MindoCore

extension AppSession {

    // MARK: - Reveal / open

    /// Show the node in Finder, scrolled to and selected.
    func revealInFinder(_ node: NodeData) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    /// Hand the file off to whatever app the user has set as the
    /// default for that UTI. Useful for images / PDFs / unknown file
    /// types that Mindo can't open in-app. Folders + workspaces just
    /// open in Finder (NSWorkspace's documented behavior).
    func openInDefaultApp(_ node: NodeData) {
        NSWorkspace.shared.open(node.url)
    }

    /// Copy the node's absolute path / workspace-relative path to the
    /// general pasteboard. Mirrors Obsidian's "Copy path" file commands.
    func copyPath(_ node: NodeData, relative: Bool) {
        let text = NodePathClipboard.text(for: node, kind: relative ? .relative : .absolute)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Open Terminal.app rooted at the node's directory (or its parent if
    /// the node is a file). Mirrors Mindolph's "Open Terminal Here".
    func openTerminal(at node: NodeData) {
        let dir = node.isFile ? node.url.deletingLastPathComponent() : node.url
        NSWorkspace.shared.open([dir],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration(),
                                completionHandler: nil)
    }

    // MARK: - Rename

    /// Prompt for a new name and rename the node on disk. Refreshes the
    /// containing workspace tree on success. Kicks the sidebar into
    /// inline-rename mode for `node`; the row swaps its label for an
    /// NSTextField. Use `renameNode(_:to:)` to commit a chosen name.
    @MainActor
    func renameNode(_ node: NodeData) {
        guard !node.isWorkspace else { return }   // workspaces use removeWorkspace, not rename
        renamingNodeID = node.id
    }

    /// Commit a rename to disk. Empty / unchanged names quietly cancel. When
    /// the chosen name is already taken, offer a unique " 2" variant rather
    /// than failing with a cryptic move error. Always clears `renamingNodeID`
    /// so the inline editor closes.
    @MainActor
    func renameNode(_ node: NodeData, to newName: String) {
        defer { renamingNodeID = nil }
        let dir = node.url.deletingLastPathComponent()
        let outcome = RenamePlan.resolve(
            current: node.name,
            desired: newName,
            exists: { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
        )
        let finalName: String
        switch outcome {
        case .unchanged:
            return
        case .ok(let name):
            finalName = name
        case .collision(let requested, let suggestion):
            // Offer the unique suggestion or cancel. Replacing the existing
            // item would be destructive, so it's not the default path.
            let alert = NSAlert()
            alert.messageText = String(format: L("sidebar.rename_collision.title"), requested)
            alert.informativeText = String(format: L("sidebar.rename_collision.message"), suggestion)
            alert.addButton(withTitle: String(format: L("sidebar.rename_collision.use_suggestion"), suggestion))
            alert.addButton(withTitle: L("button.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            finalName = suggestion
        }
        let dest = dir.appendingPathComponent(finalName)
        do {
            try FileManager.default.moveItem(at: node.url, to: dest)
            reloadWorkspace(containing: node)
        } catch {
            lastError = String(format: L("error.rename_failed"), error.localizedDescription)
        }
    }

    // MARK: - Delete (move to Trash)

    /// Move the node to the user's Trash. Safer than unlink — recoverable.
    @MainActor
    func deleteNode(_ node: NodeData) {
        guard !node.isWorkspace else { removeWorkspace(node); return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            reloadWorkspace(containing: node)
        } catch {
            lastError = String(format: L("error.delete_failed"), error.localizedDescription)
        }
    }

    /// Permanently delete a file or folder — bypasses the trash. Surfaces
    /// a confirmation alert because the action can't be undone via
    /// FileManager. Use the regular `deleteNode` for the safe Move-to-Trash
    /// behavior.
    @MainActor
    func deleteNodePermanently(_ node: NodeData) {
        guard !node.isWorkspace else { removeWorkspace(node); return }
        let alert = NSAlert()
        alert.messageText = String(format: L("sidebar.delete_permanently.title"), node.url.lastPathComponent)
        alert.informativeText = L("sidebar.delete_permanently.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("button.delete"))
        alert.addButton(withTitle: L("button.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.removeItem(at: node.url)
            reloadWorkspace(containing: node)
        } catch {
            lastError = String(format: L("error.delete_failed"), error.localizedDescription)
        }
    }

    /// Duplicate a file or folder in place, picking a unique " copy" name.
    /// Shadows Mindolph's `WorkspaceViewEditable.copyFile()` behaviour.
    @MainActor
    func duplicateNode(_ node: NodeData) {
        guard !node.isWorkspace else { return }
        let parent = node.url.deletingLastPathComponent()
        let stem = node.url.deletingPathExtension().lastPathComponent
        let ext = node.url.pathExtension
        let target = DuplicateName.uniqueURL(
            in: parent, stem: stem, ext: ext,
            exists: { FileManager.default.fileExists(atPath: $0.path) }
        )
        do {
            try FileManager.default.copyItem(at: node.url, to: target)
            reloadWorkspace(containing: node)
        } catch {
            lastError = String(format: L("error.create_failed"), error.localizedDescription)
        }
    }

    // MARK: - Copy / Paste / Move files (cross-workspace)

    /// Put the node's file URL on the general pasteboard so it can be pasted
    /// into another folder/workspace (or dragged into Finder). Mirrors
    /// Mindolph's WorkspaceViewEditable "Copy File".
    @MainActor
    func copyFileToPasteboard(_ node: NodeData) {
        guard !node.isWorkspace else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([node.url as NSURL])
    }

    /// Copy every file URL on the pasteboard into `node`'s folder (or the
    /// node's parent folder when it's a file), giving each a collision-safe
    /// name. No-op when the pasteboard carries no file URLs.
    @MainActor
    func pasteFile(into node: NodeData) {
        let dir = node.isExpandable ? node.url : node.url.deletingLastPathComponent()
        let pb = NSPasteboard.general
        guard let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return }
        let fm = FileManager.default
        var pastedAny = false
        for src in urls where fm.fileExists(atPath: src.path) {
            let dest = FileTransfer.destinationURL(
                forItemNamed: src.lastPathComponent, in: dir,
                exists: { fm.fileExists(atPath: $0.path) })
            do { try fm.copyItem(at: src, to: dest); pastedAny = true }
            catch { lastError = String(format: L("error.create_failed"), error.localizedDescription) }
        }
        if pastedAny { reloadWorkspace(containing: node) }
    }

    /// Relocate the node's file/folder into a directory chosen via an open
    /// panel — the cross-workspace "Move To…" Mindolph offers. Blocks
    /// no-op / self-nesting moves and resolves name collisions.
    @MainActor
    func moveNodeToFolder(_ node: NodeData) {
        guard !node.isWorkspace else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("sidebar.menu.move_to")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        guard !FileTransfer.isRedundantOrInvalidMove(source: node.url, intoDirectory: dir) else { return }
        let fm = FileManager.default
        let dest = FileTransfer.destinationURL(
            forItemNamed: node.url.lastPathComponent, in: dir,
            exists: { fm.fileExists(atPath: $0.path) })
        do {
            try fm.moveItem(at: node.url, to: dest)
            reloadAllWorkspaces()
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }

    // MARK: - Create

    /// Prompt for a filename and create an empty file inside `node`'s folder.
    /// `extension` (default "md") drives the prefilled name and the file's
    /// resulting extension; matches the sidebar's per-type New File submenu.
    @MainActor
    func createFile(in node: NodeData, extension ext: String = "md") {
        guard node.isExpandable else { return }
        guard let name = promptString(
            title: L("sidebar.new_file.title"),
            message: L("sidebar.new_file.message"),
            initial: "Untitled.\(ext)"
        ), !name.isEmpty else { return }
        let url = node.url.appendingPathComponent(name)
        do {
            try Data().write(to: url, options: .withoutOverwriting)
            reloadWorkspace(containing: node)
            open(url: url)
        } catch {
            lastError = String(format: L("error.create_failed"), error.localizedDescription)
        }
    }

    /// Prompt for a folder name and create it inside `node`'s folder.
    @MainActor
    func createFolder(in node: NodeData) {
        guard node.isExpandable else { return }
        guard let name = promptString(
            title: L("sidebar.new_folder.title"),
            message: L("sidebar.new_folder.message"),
            initial: "New Folder"
        ), !name.isEmpty else { return }
        let url = node.url.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            reloadWorkspace(containing: node)
        } catch {
            lastError = String(format: L("error.create_failed"), error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// Walk up to the owning workspace root, reload its children, and re-publish.
    private func reloadWorkspace(containing node: NodeData) {
        let root = node.workspace ?? node
        root.reloadChildren()
        // Trigger @Observable to re-emit by reassigning the array.
        workspaceRoots = workspaceRoots
    }

    /// Reload every workspace root with the current preferences (e.g.
    /// after the user flips Show Hidden Files in Preferences). Walks
    /// only the root level — deeper folders re-load lazily on expand.
    @MainActor
    func reloadAllWorkspaces() {
        let cfg = WorkspaceConfig.fromPreferences()
        for root in workspaceRoots { root.reloadChildren(config: cfg) }
        workspaceRoots = workspaceRoots
    }

    /// Single-line text prompt — same shape as the markdown editor's
    /// promptString helper but lives here so the sidebar context menu
    /// doesn't have to reach into MindoMarkdown.
    @MainActor
    private func promptString(title: String, message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L("button.ok"))
        alert.addButton(withTitle: L("button.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
