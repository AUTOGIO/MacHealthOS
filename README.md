# Mac Health OS

Native macOS SwiftUI app for local, read-only Mac health checks, report generation, guarded maintenance, and optional on-device AI explanations (Ollama / LM Studio / OpenAI).

## Run

Requires macOS 14+, Apple Silicon, and Swift 6 (Xcode or Command Line Tools).

> [!NOTE]
> **iCloud-synced directories:** If you clone or run this project inside a directory managed by iCloud Drive (such as `Desktop` or `Documents`), building or testing using standard commands may fail due to code signing conflicts with FileProvider attributes. 
> To bypass this, run tests and build via the provided helper scripts:
> ```bash
> ./scripts/test.sh                   # runs test suite with custom scratch path
> ./scripts/build_and_run.sh          # builds and runs app with custom scratch path
> ./scripts/build_and_run.sh --verify # launch and confirm process
> ```
> Otherwise, run in a directory that is not synced by iCloud.

Standard clean builds outside iCloud:
```bash
swift build && swift test
```

## Where things live

- `Sources/` — app code · `Tests/` — tests · `scripts/` — helpers
- `assets/` — images · `docs/` — guides (runbook, security, changelog)
- `dist/` — local build output (gitignored; recreated by the run script)
- Reports are written under `~/Reports/MacHealthOS/`

More detail: `docs/user-guide.md`, `docs/runbook.md`, `docs/security.md`, `AGENTS.md`.
