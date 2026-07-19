import SwiftUI

struct PreferencesView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        Form {
            Section("Reports") {
                LabeledContent("Report folder") {
                    Text(appModel.reportsDirectoryDisplayText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Button("Open Report Folder") {
                    appModel.openReportsFolder()
                }
            }

            Section("AI Provider") {
                Picker("Provider", selection: $appModel.aiProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName)
                            .tag(provider)
                    }
                }

                LabeledContent("Default safety") {
                    Text("AI is disabled by default.")
                        .foregroundStyle(.secondary)
                }

                Stepper(value: $appModel.aiTimeoutSeconds, in: 5...120, step: 5) {
                    LabeledContent("Timeout") {
                        Text("\(Int(appModel.aiTimeoutSeconds)) seconds")
                            .monospacedDigit()
                    }
                }
            }

            Section("Local AI (LM Studio)") {
                TextField("Base URL", text: $appModel.localAIBaseURL)
                    .textFieldStyle(.roundedBorder)

                TextField("Model Name", text: $appModel.localAIModelName)
                    .textFieldStyle(.roundedBorder)

                Text("Expected endpoint: `http://localhost:1234/v1/chat/completions`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local AI (Ollama)") {
                TextField("Base URL", text: $appModel.ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)

                TextField("Model Name", text: $appModel.ollamaModelName)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button(appModel.isRefreshingOllamaModels ? "Refreshing…" : "Refresh Live Models") {
                        appModel.refreshOllamaModels()
                    }
                    .disabled(appModel.isRefreshingOllamaModels)

                    if let firstModel = appModel.discoveredOllamaModels.first {
                        Button("Use First Live Model") {
                            appModel.useOllamaModel(firstModel.name)
                        }
                    }
                }

                Text(appModel.ollamaRefreshStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(appModel.ollamaConfiguredModelStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !appModel.discoveredOllamaModels.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appModel.discoveredOllamaModels) { model in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(.subheadline.weight(.medium))

                                    Text(ollamaDetailLine(for: model))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if appModel.ollamaModelName == model.name {
                                    Text("Selected")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("Use") {
                                        appModel.useOllamaModel(model.name)
                                    }
                                }
                            }
                        }
                    }
                }

                Text("Refresh uses `\(appModel.ollamaBaseURL)/api/tags`. AI explanations use the OpenAI-compatible Ollama chat endpoint under the same base URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenAI") {
                TextField("Model Name", text: $appModel.openAIModelName)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: $appModel.openAIAPIKeyDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button("Save Key") {
                        appModel.saveOpenAIAPIKey()
                    }

                    Button("Clear Key", role: .destructive) {
                        appModel.clearOpenAIAPIKey()
                    }
                    .disabled(!appModel.isOpenAIAPIKeyStored && appModel.openAIAPIKeyDraft.isEmpty)
                }

                Text(appModel.openAIKeyStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Application") {
                LabeledContent("Current status") {
                    Text(appModel.lastStatusMessage)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Latest scan") {
                    Text(appModel.latestScanDisplayText)
                        .monospacedDigit()
                }

                LabeledContent("Latest AI explanation") {
                    Text(appModel.latestAIExplanationTimestampText)
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 680, height: 700)
    }

    private func ollamaDetailLine(for model: OllamaModelSummary) -> String {
        var parts: [String] = []

        if let family = model.family, !family.isEmpty {
            parts.append(family)
        }

        if let parameterSize = model.parameterSize, !parameterSize.isEmpty {
            parts.append(parameterSize)
        }

        if let quantizationLevel = model.quantizationLevel, !quantizationLevel.isEmpty {
            parts.append(quantizationLevel)
        }

        if let sizeBytes = model.sizeBytes {
            parts.append(StorageFormatters.byteCountString(from: sizeBytes))
        }

        return parts.isEmpty ? "No additional metadata available." : parts.joined(separator: " • ")
    }
}
