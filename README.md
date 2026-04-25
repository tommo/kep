# Mindo

A native macOS port of [Mindolph](https://github.com/mindolph/Mindolph) — personal-knowledge-management with mind maps, markdown, PlantUML, CSV, and multi-provider LLM integration.

Source-of-truth for behavior parity is the Java original at `../javamind`. See `docs/architecture.md` for the module map.

## Status

Early scaffolding. Track progress via the `mindo-swift-port` kanban project.

## Build

```bash
swift build
swift test
```

## Interactive testing

Three ways to actually run the app:

### 1. Quick — `swift run`

```bash
swift run Mindo
```

The window opens immediately and is brought to the foreground (the
`MindoAppDelegate` calls `NSApp.activate(ignoringOtherApps: true)`).
First-time UX: the sidebar is empty — use **File → Open Workspace…**
to pick a folder (e.g. `../javamind/DemoWorkspace`).

### 2. Recommended — Xcode

```bash
open Package.swift
```

Pick the **Mindo** scheme, ⌘R. Breakpoints, view debugger, SwiftUI
previews, and the memory graph all work.

### 3. Real `.app` bundle

```bash
./Scripts/make-app.sh
open build/Mindo.app
```

Produces `build/Mindo.app` with `Info.plist`, file-type associations
(`.mmd` / `.md` / `.puml` / `.mm`), and Dock support. `CONFIG=debug
./Scripts/make-app.sh` for a debug build.

### Sample data

- `../javamind/DemoWorkspace/MindMap.mmd` — Mindolph's full demo file,
  great for testing the canvas (round-trips through our parser).
- `../javamind/DemoWorkspace/Markdown.md` — exercises the markdown
  editor + WKWebView preview.
- `../javamind/DemoWorkspace/PlantUML/*.puml` — PlantUML samples; run
  `brew install plantuml graphviz` first or you'll see the install hint.
- `../javamind/DemoWorkspace/CSV.csv` — drives the CSV table editor.

### Test scenarios worth a sweep

- Open a workspace via the **+** button (or **File → Open Workspace…**)
  — the sidebar walks the tree lazily, sorted folders-before-files.
- Click any `.mmd`. Try **Tab** (add child), **Enter** (sibling),
  **Delete** (remove), **-/=** (collapse/expand), **arrow keys**, ⌘Z /
  ⌘⇧Z (undo/redo), drag a topic onto another to reparent.
- Right-click a topic → **Add Note / Link / File / Image** (Image opens
  NSOpenPanel and base64-embeds the file).
- ⌘⇧J — **Insert Snippet…** (filtered by active file type).
- ⌘⇧G — **AI Generate…** (configure provider in **AI → Settings…** first;
  the OpenAI / Ollama / DeepSeek / Moonshot / Qwen providers are wired,
  Gemini / HuggingFace / ChatGLM stubbed).
- **File → Import FreeMind…** to convert `.mm` files.
- **File → Export → Markdown to PDF…** when a `.md` doc is active.
- **Window → Show / Hide Outline** (⌘⌥0), **Next / Previous Tab**
  (⌘⇧] / ⌘⇧[).

## Layout

```
Sources/
  MindoModel/      .mmd parser/writer + Topic/Extra/MindMap (no UI)
  MindoCore/       Workspace/Project/NodeData + file watching
  MindoBase/       Editor protocols, theme, font icons
  MindoMindMap/    Mind map canvas (NSView) + editor
  MindoMarkdown/   Markdown editor with WKWebView preview
  MindoPlantUML/   PlantUML editor (subprocess to plantuml.jar)
  MindoCSV/        Visual CSV table editor
  MindoGenAI/      LLM provider abstraction + chat panes
  Mindo/           AppKit/SwiftUI app shell wiring everything
```
