# Mac Health OS Runbook

## First Run Checklist

1. Confirm Xcode Command Line Tools are available.
2. Build the package with `swift build`.
3. Launch the app with `./scripts/build_and_run.sh`.
4. Confirm the menu bar item appears.
5. Open the dashboard window.
6. Run `Analyze My Mac`.
7. If prompted, grant only the folder access you want the app to use.
8. Generate a report and confirm both Markdown and JSON files appear in `~/Reports/MacHealthOS/`.
9. Open Preferences and confirm AI is still set to `Disabled`.

## How To Run A Scan

From the dashboard:

1. Click `Analyze My Mac`.
2. Wait for the latest scan timestamp and category states to refresh.
3. Review the storage, performance, security, and automation sections.

From the menu bar:

1. Click the menu bar item.
2. Select `Run Quick Check`.
3. Open the dashboard if you want to inspect the full results.

## How To Generate A Report

From the dashboard:

1. Click `Generate Report`.
2. The app writes both Markdown and JSON using the same `HealthReport`.
3. The latest report is opened and revealed in Finder.

From the menu bar:

1. Click the menu bar item.
2. Select `Generate Report`.

## How To Enable Local AI

### Ollama

1. Start Ollama locally.
2. Open `Preferences`.
3. Set `Provider` to `Ollama`.
4. Confirm the base URL is `http://localhost:11434`.
5. Click `Refresh Live Models`.
6. Select a live model from the returned list or use the first live model shortcut.
7. Return to the dashboard and click `Explain with AI`.

### LM Studio

1. Start LM Studio and expose the local chat completions endpoint.
2. Open `Preferences`.
3. Set `Provider` to `Local AI (LM Studio)`.
4. Set the base URL to `http://localhost:1234/v1/chat/completions`.
5. Set the model name to the loaded local model.
6. Adjust timeout if needed.
7. Return to the dashboard and click `Explain with AI`.

## How To Enable OpenAI

1. Open `Preferences`.
2. Set `Provider` to `OpenAI`.
3. Enter the model name.
4. Enter the API key in the secure field.
5. Click `Save Key`.
6. Confirm the status changes to `Stored in macOS Keychain.`
7. Return to the dashboard and click `Explain with AI`.

## How To Disable AI

1. Open `Preferences`.
2. Set `Provider` to `Disabled`.
3. Optionally click `Clear Key` if you no longer want the OpenAI key stored in Keychain.

## How To Interpret Health Score

- The score is weighted across storage, performance, security, automation, and maintenance freshness.
- Unknown data does not count as healthy.
- The dashboard and report both expose `Unknown`, `Healthy`, `Warning`, or `Critical` states per category.
- The report also includes the top issues and maintenance recommendations derived from the real model state.

## Safe Maintenance Actions

Available actions:

- Empty Trash
- Clear selected user cache subfolders
- Open Downloads folder for review
- Open Login Items settings
- Prepare DNS cache flush command
- Prepare Spotlight reindex command
- Generate maintenance report

Operational rules:

- Destructive user-scope actions require confirmation.
- DNS flush and Spotlight reindex are never run automatically.
- The app prefers Finder and System Settings where possible.

## Troubleshooting

If the app does not launch:

- Run `swift build` to confirm the package still compiles.
- Run `./scripts/build_and_run.sh --verify`.
- Check that the built app bundle exists under `dist/`.

If diagnostics stay `Unknown`:

- Run `Analyze My Mac` again.
- Check whether macOS denied access to the relevant folder.
- Expect some system-level values to remain unavailable for the current user.

If report generation fails:

- Confirm `~/Reports/MacHealthOS/` is writable.
- Generate the report again from the dashboard.
- Confirm both `.md` and `.json` files were created together.

If LM Studio explanation fails:

- Confirm LM Studio is running.
- Confirm the configured base URL is correct.
- Confirm the model name matches the served model.

If Ollama explanation fails:

- Confirm Ollama is running on `http://localhost:11434`.
- Click `Refresh Live Models` and confirm a live model is returned.
- Confirm the selected model still appears in the live list.

If OpenAI explanation fails:

- Confirm `Provider` is set to `OpenAI`.
- Confirm an API key is stored in Keychain.
- Confirm network access is available.

## App Intents Status

App Intents are not enabled in this build. They are intentionally deferred until there is a stable bundle-and-distribution path beyond the current SwiftPM-first app packaging flow.
