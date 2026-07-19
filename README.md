# Mac Health OS

Native macOS SwiftUI app for local, read-only Mac health checks, report generation, guarded maintenance, and optional on-device AI explanations (Ollama / LM Studio / OpenAI).

## Run

Requires macOS 14+, Apple Silicon, and Swift 6 (Xcode or Command Line Tools).

```bash
swift build && swift test
./scripts/build_and_run.sh          # build + open the app
./scripts/build_and_run.sh --verify # launch and confirm process
```

## Where things live

- `Sources/` — app code · `Tests/` — tests · `scripts/` — helpers
- `assets/` — images · `docs/` — guides (runbook, security, changelog)
- `dist/` — local build output (gitignored; recreated by the run script)
- Reports are written under `~/Reports/MacHealthOS/`

More detail: `docs/user-guide.md`, `docs/runbook.md`, `docs/security.md`, `AGENTS.md`.
