# Espresso Knowledge Base — agentic test-drive artifact

This folder is **not hand-written**. Every document here was authored by Kep's
own in-app GenAI engine (DeepSeek `deepseek-chat`, via the same `LLMProvider` +
`LLMInput` path that the `AIGenerate` panel drives), then saved unmodified. It
doubles as an example vault *and* as evidence for how the agentic tool behaves on
a realistic, multi-format authoring goal.

It demonstrates Kep as a small knowledge base:

- **Home.md** — index page, cross-linking every note with `[[wiki links]]`.
- **Extraction.md**, **Grind.md** — Markdown notes with tables and `[[links]]`.
- **Brewing Process.puml** — a PlantUML activity diagram.
- **Bean Origins.csv** — a CSV table.
- **Espresso Map.mmd** — a Kep mind map.

All `[[wiki links]]` resolve across the folder (they match by base name, so
`[[Brewing Process]]` → `Brewing Process.puml`, `[[Espresso Map]]` →
`Espresso Map.mmd`).

## Reproduce it

```sh
KEP_AI_TESTDRIVE=1 DEEPSEEK_API_KEY=… swift test --filter AgenticTestdrive
```

(The harness lives at `Tests/KepMindMapTests/AgenticTestdrive.swift`; it is
skipped in normal test runs.)

## Known defects — left in on purpose

The Markdown prose came out genuinely good. The *structured* formats did not,
and the tool shipped them without complaint — see `_testdrive-report.md`:

- **Bean Origins.csv** is malformed: the model put commas inside unquoted
  "Flavor Notes" values, so rows have 7 fields against a 5-field header.
- **Brewing Process.puml** contains a bare `repeat` with no matching
  `repeat while (…)` — PlantUML will report a syntax error.
- **Espresso Map.mmd** is flat: 12 sibling topics under the root, no hierarchy
  (the tool can only append flat children).

These are kept verbatim because the point of the test-drive is to show *where the
agentic tool needs guardrails* (validated/structured output), not to polish them
away. See the evaluation on kanban epic #194.
