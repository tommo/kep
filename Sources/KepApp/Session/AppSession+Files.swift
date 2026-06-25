import AppKit
import KepCore

extension AppSession {

    // MARK: - Reveal / open

    /// Show the node in Finder, scrolled to and selected.
    func revealInFinder(_ node: NodeData) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    /// Hand the file off to whatever app the user has set as the
    /// default for that UTI. Useful for images / PDFs / unknown file
    /// types that Kep can't open in-app. Folders + workspaces just
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
        renamingNodeURL = node.url.standardizedFileURL   // sidebar swaps the row for an inline field
    }

    /// Commit a rename to disk. Empty / unchanged names quietly cancel. When
    /// the chosen name is already taken, offer a unique " 2" variant rather
    /// than failing with a cryptic move error. Always clears `renamingNodeID`
    /// so the inline editor closes.
    @MainActor
    func renameNode(_ node: NodeData, to newName: String) {
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
            retargetOpenDocuments(movedFrom: node.url, to: dest)
            reloadWorkspace(containing: node)
        } catch {
            lastError = String(format: L("error.rename_failed"), error.localizedDescription)
        }
    }

    /// After a file/folder is renamed (moved) on disk, point any open tab at the
    /// new path and refresh its title, so the tab bar reflects the new name and
    /// saves still land on the right file. Handles folder renames by rewriting
    /// the path prefix of every open document living inside it.
    @MainActor
    func retargetOpenDocuments(movedFrom oldURL: URL, to newURL: URL) {
        let oldStd = oldURL.standardizedFileURL
        let oldPath = oldStd.path
        var changed = false
        for idx in openDocuments.indices {
            guard let docURL = openDocuments[idx].fileURL?.standardizedFileURL else { continue }
            let newDocURL: URL
            if docURL == oldStd {
                newDocURL = newURL                                   // the renamed file itself
            } else if docURL.path.hasPrefix(oldPath + "/") {
                let suffix = String(docURL.path.dropFirst(oldPath.count))   // keeps leading "/"
                newDocURL = URL(fileURLWithPath: newURL.path + suffix)      // inside a renamed folder
            } else {
                continue
            }
            openDocuments[idx].fileURL = newDocURL
            openDocuments[idx].title = newDocURL.lastPathComponent
            changed = true
        }
        if changed { persistOpenTabs() }
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
        createDocumentOnDisk(extension: ext, in: node)
    }

    /// Obsidian-style new document: write a real file to `folder` with a unique
    /// default name (no save panel, no name dialog), reveal it, open it, and
    /// start an inline rename so the user can name it in place.
    @discardableResult
    func createDocumentOnDisk(extension ext: String, in folder: NodeData, starter: Data = Data()) -> URL? {
        let url = Self.uniqueFileURL(in: folder.url, base: "Untitled", ext: ext)
        do {
            try starter.write(to: url, options: .withoutOverwriting)
        } catch {
            lastError = String(format: L("error.create_failed"), error.localizedDescription)
            return nil
        }
        setFolderExpanded(folder.url, isWorkspace: folder.isWorkspace, true)
        reloadWorkspace(containing: folder)
        // Open the doc (it becomes the active tab) but DON'T grab editor focus —
        // instead drop the new sidebar row straight into inline rename so you can
        // name it immediately (Enter commits and hands focus back to the list;
        // Esc keeps the "Untitled" name). The new node exists now that the
        // workspace reloaded above.
        open(url: url, focusEditor: false)
        renamingNodeURL = url.standardizedFileURL
        return url
    }

    /// `Untitled.ext`, or `Untitled 1.ext`, `Untitled 2.ext`, … if taken.
    static func uniqueFileURL(in dir: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    /// The folder a new document should land in: the active document's folder,
    /// else the first workspace root. nil when no workspace is open.
    func defaultCreationFolder() -> NodeData? {
        if let activeURL = activeDocument?.fileURL,
           let node = nodeForURL(activeURL.deletingLastPathComponent()) {
            return node
        }
        return workspaceRoots.first
    }

    /// Find the loaded sidebar node for a URL, descending only along its path.
    func nodeForURL(_ url: URL) -> NodeData? {
        let target = url.standardizedFileURL
        for root in workspaceRoots {
            if let n = Self.descend(root, to: target) { return n }
        }
        return nil
    }

    private static func descend(_ node: NodeData, to target: URL) -> NodeData? {
        let here = node.url.standardizedFileURL
        if here == target { return node }
        guard target.path.hasPrefix(here.path + "/") else { return nil }
        for child in node.children() {
            if let found = descend(child, to: target) { return found }
        }
        return nil
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
        sidebarReloadToken &+= 1
        workspaceContentVersion &+= 1
    }

    /// Reload every workspace root with the current preferences (e.g.
    /// after the user flips Show Hidden Files in Preferences). Walks
    /// only the root level — deeper folders re-load lazily on expand.
    @MainActor
    func reloadAllWorkspaces() {
        let cfg = WorkspaceConfig.fromPreferences()
        for root in workspaceRoots { root.reloadChildren(config: cfg) }
        workspaceRoots = workspaceRoots
        sidebarReloadToken &+= 1
        workspaceContentVersion &+= 1
    }

    /// Single-line text prompt — same shape as the markdown editor's
    /// promptString helper but lives here so the sidebar context menu
    /// doesn't have to reach into KepMarkdown.
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
