# Mac Health OS — user guide

## What the app does

- Launches as a regular macOS app with a Dock presence and a menu bar item.
- Opens a dashboard with health score, storage, performance, security, automation, latest scan, and latest report state.
- Runs local diagnostics on demand with no fake values.
- Generates Markdown and JSON reports from the same `HealthReport` model.
- Stores reports under `~/Reports/MacHealthOS/`.
- Offers guarded maintenance actions for user-scope cleanup and review.
- Supports optional AI explanation with Ollama, LM Studio, or OpenAI.

## What the app does not do

- Upload diagnostics automatically; no telemetry, analytics, or cloud sync.
- Claim antivirus or malware removal capability.
- Perform destructive maintenance without confirmation, or run `sudo` automatically.
- Remove LaunchAgents, kill processes, or disable security protections automatically.
- Invent diagnostic values when data is unavailable.

## Permissions

- Storage scan stays inside user-home locations by default.
- macOS may prompt for access to folders such as `Downloads`.
- Security checks use native tools such as `spctl`, `fdesetup`, and `csrutil`.
- OpenAI API keys are stored in macOS Keychain only.
- Network calls (OpenAI or local Ollama/LM Studio) happen only when you explicitly request AI actions.

## Reports

Folder: `~/Reports/MacHealthOS/`

- `mac_health_os_YYYY-MM-DD_HH-mm-ss.md`
- `mac_health_os_YYYY-MM-DD_HH-mm-ss.json`

Each report includes timestamp, machine name, macOS version, hardware architecture, health score, storage/performance/security/automation findings, maintenance recommendations, and the maintenance action log. JSON reports are validated by decoding immediately after write.

## Safety model

- Diagnostics are read-only. Unknown data is not treated as healthy.
- Maintenance actions are explicit, user-triggered, and confirmation-gated.
- Trash deletion only targets `~/.Trash`. Cache clearing only targets selected subfolders inside `~/Library/Caches`.
- DNS flush and Spotlight reindex are prepared for manual execution only.

## AI setup

AI is disabled by default.

### Ollama

1. Start Ollama locally.
2. Preferences → provider `Ollama` → base URL `http://localhost:11434`.
3. Click `Refresh Live Models`, select a model, then `Explain with AI` on the dashboard.

### LM Studio

1. Start LM Studio, load a chat model, enable the local server.
2. Preferences → `Local AI (LM Studio)` → base URL `http://localhost:1234/v1/chat/completions`.
3. Set the local model name, then `Explain with AI` when ready.

### OpenAI

1. Preferences → `OpenAI` → model name → enter API key → `Save Key`.
2. Key stays in Keychain; never written to report files. No request until you click `Explain with AI`.

## Menu bar and dashboard

Menu bar: Open Dashboard, Run Quick Check, Generate Report, Open Latest Report, Preferences, Quit.

Dashboard: Analyze My Mac, Generate Report, Explain with AI, Run Safe Maintenance.

## Known limitations

- App Intents are deferred in this build.
- Some diagnostics may remain `Unknown` when permissions are denied.
- AI explanations summarize existing findings only and fail clearly if the provider is unavailable.
