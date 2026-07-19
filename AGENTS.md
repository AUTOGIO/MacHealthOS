# MacHealthOS — agent notes

Native macOS SwiftUI app (Swift Package Manager). Prefer MOVE over copy; do not invent new top-level folders.

## Folder layout

| Path | Purpose |
|------|---------|
| `Sources/` | Application code (SPM equivalent of `src/`; do not rename) |
| `Tests/` | Tests only (SPM convention; do not rename) |
| `scripts/` | Runnable helpers (`.sh`, `.zsh`, `.command`) |
| `config/` | Non-secret settings (create only when needed) |
| `data/` | CSV, Excel, exports, raw inputs |
| `assets/` | Images, icons, logos |
| `docs/` | Markdown guides, design notes |
| `docs/prompts/` | AI prompt files |
| `archive/` | Obsolete files kept for reference |
| Root | Only `README.md`, `AGENTS.md`, `.gitignore`, and toolchain files (`Package.swift`, etc.) |

## Rules

- Do not redesign features or rewrite the app unless required for a safe move.
- Do not commit secrets (`.env`, API keys, Keychain material).
- Do not put personal machine inventory in this file.
- Prefer editing existing files over creating new ones.
- After moves, fix broken paths in docs and scripts.
