# Changelog

## 2026-06-25

- Bootstrapped the first running Mac Health OS SwiftUI app shell.
- Added a dashboard window with placeholder `Unknown` status fields.
- Added a menu bar item with dashboard, quick check, report, preferences, and quit actions.
- Added local Markdown and JSON report generation with real timestamps, JSON decode validation, and Finder reveal support.
- Added a project-local `scripts/build_and_run.sh` launcher and Codex Run action wiring.
- Added real read-only storage diagnostics for disk capacity, Downloads, Trash, Caches, large files, and old Downloads files.
- Added the health scoring engine, report/recommendation models, and unit coverage for scoring behavior.
- Added a safe fixed-path command runner plus a real read-only performance diagnostics module for CPU, memory, uptime, top processes, and GUI-domain background services.
- Added a real read-only security diagnostics module for Gatekeeper, FileVault, SIP, firewall, XProtect receipts, and visible software updates.
- Updated the dashboard to show real storage and performance detail sections and on-demand recommendations.
- Updated the dashboard and scoring flow to include live security status, security recommendations, and security unit coverage.
- Added a real read-only automation diagnostics module for LaunchAgents, automation folders, KeepAlive detection, plist validation, missing executable checks, stale log path checks, and Homebrew service visibility.
- Updated the dashboard and health scoring flow to include live automation status, automation recommendations, and automation unit coverage.
- Added guarded safe maintenance actions for emptying user Trash, clearing selected user cache folders, opening Downloads, opening Login Items settings, preparing DNS flush commands, preparing Spotlight reindex commands, and generating maintenance reports.
- Added Preferences-based AI configuration with disabled-by-default provider selection, LM Studio support, OpenAI model configuration, timeout control, and OpenAI Keychain storage.
- Added advisory AI explanation support that summarizes only the generated local report and fails clearly when the provider is unavailable or misconfigured.
- Added Ollama as a dedicated local AI provider with explicit live model refresh from `/api/tags`, per-model selection in Preferences, and OpenAI-compatible local chat requests over `localhost`.
- Added runbook and security documentation covering the local-first model, permissions, report locations, AI setup, and safety limits.
- Documented App Intents as intentionally pending to keep the SwiftPM app bundle stable in this delivery.
