import AppKit
import MindoCore

extension AppSession {

    // MARK: - Reveal / open

    /// Show the node in Finder, scrolled to and selected.
    func revealInFinder(_ node: NodeData) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
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
    /// containing workspace tree on success.
    @MainActor
    func renameNode(_ node: NodeData) {
        guard !node.isWorkspace else { return }   // workspaces use removeWorkspace, not rename
        guard let newName = promptString(
            title: L("sidebar.rename.title"),
            message: L("sidebar.rename.message"),
            initial: node.name
        ), newName != node.name else { return }

        let dest = node.url.deletingLastPathComponent().appendingPathComponent(newName)
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

    // MARK: - Create

    /// Prompt for a filename and create an empty file inside `node`'s folder.
    @MainActor
    func createFile(in node: NodeData) {
        guard node.isExpandable else { return }
        guard let name = promptString(
            title: L("sidebar.new_file.title"),
            message: L("sidebar.new_file.message"),
            initial: "Untitled.md"
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
