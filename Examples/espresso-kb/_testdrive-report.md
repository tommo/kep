# Agentic test-drive report

Engine: DeepSeek `deepseek-chat` via Mindo's `LLMProvider` — the same path `AIGeneratePane` drives.
Authored 5 text docs + 1 mind map. Each entry: validation · size · output tokens · latency.

- **Home.md** — ✅ ok · 251 chars · 57 tok · 1.6s
- **Extraction.md** — ✅ ok · 1991 chars · 501 tok · 7.1s
- **Grind.md** — ✅ ok · 2274 chars · 533 tok · 8.7s
- **Brewing Process.puml** — ✅ ok · 232 chars · 76 tok · 1.7s
- **Bean Origins.csv** — ✅ ok · 651 chars · 208 tok · 3.5s
- **Espresso Map.mmd** — ✅ parses · 12 flat children · 47 tok · 1.7s

> Mind-map note: the in-app tool can only add **flat children under the root** — it cannot author nested hierarchy, and the model cannot emit Mindo's `.mmd` wire format directly. The map above is the realistic ceiling.
