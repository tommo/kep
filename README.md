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
