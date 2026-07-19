# Security Model

## Local-First Model

Mac Health OS is designed for local-first operation on macOS. Core diagnostics, scoring, report generation, and maintenance actions run on the local machine.

## What Data Is Collected

The app may collect and display:

- machine name
- macOS version
- hardware architecture
- local storage metrics in approved user-home paths
- process, memory, uptime, and background-service summaries
- Gatekeeper, FileVault, SIP, firewall, and visible update status
- LaunchAgent metadata and automation folder state
- local maintenance action history inside the in-memory report model

Generated reports may include local file paths, process names, service labels, and system-status findings relevant to the health report.

## What Data Is Never Collected

- browser telemetry
- background usage analytics
- advertising identifiers
- passwords
- private tokens
- API keys in report files
- hidden cloud telemetry

The app does not send diagnostics anywhere unless you explicitly choose an AI provider and request an AI-related action such as `Explain with AI` or, for Ollama only, `Refresh Live Models`.

## AI Privacy Implications

AI is disabled by default.

When enabled:

- Ollama mode sends the generated local report only to the configured local Ollama endpoint. Live model refresh queries the local `/api/tags` endpoint only when you explicitly request it.
- LM Studio mode sends the generated local report only to the configured local endpoint.
- OpenAI mode sends the generated local report only to the OpenAI API when you explicitly request an AI explanation.
- AI is advisory only and must not be treated as the source of system facts.

The app does not ask the AI system to create new findings. It sends the current local report for summarization and explanation only.

## Keychain Storage

- OpenAI API keys are stored in macOS Keychain.
- OpenAI API keys are not stored in plain text project files.
- OpenAI API keys are not printed in normal app flows.

## Deletion Safeguards

- No destructive maintenance action runs without explicit confirmation.
- Trash cleanup only targets `~/.Trash`.
- Cache cleanup only targets selected subfolders inside `~/Library/Caches`.
- DNS flush and Spotlight reindex are prepared for manual execution only.
- The app does not disable security protections, remove LaunchAgents automatically, or kill processes automatically.

## No Telemetry

Mac Health OS does not include telemetry, analytics, crash reporting, or background data export in this build.
