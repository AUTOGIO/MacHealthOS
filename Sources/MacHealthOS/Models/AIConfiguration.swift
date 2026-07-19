import Foundation

enum AIProvider: String, Codable, CaseIterable, Sendable {
    case disabled
    case lmStudio
    case ollama
    case openAI

    var displayName: String {
        switch self {
        case .disabled:
            "Disabled"
        case .lmStudio:
            "Local AI (LM Studio)"
        case .ollama:
            "Ollama"
        case .openAI:
            "OpenAI"
        }
    }
}

struct AIConfiguration: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case provider
        case localBaseURL
        case localModelName
        case ollamaBaseURL
        case ollamaModelName
        case timeoutSeconds
        case openAIModelName
    }

    var provider: AIProvider
    var localBaseURL: String
    var localModelName: String
    var ollamaBaseURL: String
    var ollamaModelName: String
    var timeoutSeconds: Double
    var openAIModelName: String

    static let `default` = AIConfiguration(
        provider: .disabled,
        localBaseURL: "http://localhost:1234/v1/chat/completions",
        localModelName: "local-model",
        ollamaBaseURL: "http://localhost:11434",
        ollamaModelName: "",
        timeoutSeconds: 30,
        openAIModelName: "gpt-4.1-mini"
    )

    init(
        provider: AIProvider,
        localBaseURL: String,
        localModelName: String,
        ollamaBaseURL: String,
        ollamaModelName: String,
        timeoutSeconds: Double,
        openAIModelName: String
    ) {
        self.provider = provider
        self.localBaseURL = localBaseURL
        self.localModelName = localModelName
        self.ollamaBaseURL = ollamaBaseURL
        self.ollamaModelName = ollamaModelName
        self.timeoutSeconds = timeoutSeconds
        self.openAIModelName = openAIModelName
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AIConfiguration.default

        provider = try container.decodeIfPresent(AIProvider.self, forKey: .provider) ?? defaults.provider
        localBaseURL = try container.decodeIfPresent(String.self, forKey: .localBaseURL) ?? defaults.localBaseURL
        localModelName = try container.decodeIfPresent(String.self, forKey: .localModelName) ?? defaults.localModelName
        ollamaBaseURL = try container.decodeIfPresent(String.self, forKey: .ollamaBaseURL) ?? defaults.ollamaBaseURL
        ollamaModelName = try container.decodeIfPresent(String.self, forKey: .ollamaModelName) ?? defaults.ollamaModelName
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? defaults.timeoutSeconds
        openAIModelName = try container.decodeIfPresent(String.self, forKey: .openAIModelName) ?? defaults.openAIModelName
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(localBaseURL, forKey: .localBaseURL)
        try container.encode(localModelName, forKey: .localModelName)
        try container.encode(ollamaBaseURL, forKey: .ollamaBaseURL)
        try container.encode(ollamaModelName, forKey: .ollamaModelName)
        try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try container.encode(openAIModelName, forKey: .openAIModelName)
    }
}

struct AIExplanation: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let generatedAt: Date
    let provider: AIProvider
    let disclaimer: String
    let normalConditions: [String]
    let realRisks: [String]
    let expectedBehavior: [String]
    let unknownOrUnavailable: [String]
    let recommendedNextSteps: [String]

    init(
        id: UUID = UUID(),
        generatedAt: Date = Date(),
        provider: AIProvider,
        disclaimer: String,
        normalConditions: [String],
        realRisks: [String],
        expectedBehavior: [String],
        unknownOrUnavailable: [String],
        recommendedNextSteps: [String]
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.provider = provider
        self.disclaimer = disclaimer
        self.normalConditions = normalConditions
        self.realRisks = realRisks
        self.expectedBehavior = expectedBehavior
        self.unknownOrUnavailable = unknownOrUnavailable
        self.recommendedNextSteps = recommendedNextSteps
    }

    var sections: [AIExplanationSection] {
        [
            AIExplanationSection(title: "Normal Conditions", items: normalConditions),
            AIExplanationSection(title: "Real Risks", items: realRisks),
            AIExplanationSection(title: "Expected Behavior", items: expectedBehavior),
            AIExplanationSection(title: "Unknown or Unavailable", items: unknownOrUnavailable),
            AIExplanationSection(title: "Recommended Next Steps", items: recommendedNextSteps),
        ]
    }

    var content: String {
        sections.map(\.formattedText).joined(separator: "\n\n")
    }
}

struct AIExplanationSection: Codable, Equatable, Sendable, Identifiable {
    let title: String
    let items: [String]

    var id: String {
        title
    }

    var formattedText: String {
        let lines: [String]

        if items.isEmpty {
            lines = ["- None."]
        } else {
            lines = items.map { "- \($0)" }
        }

        return ([title] + lines).joined(separator: "\n")
    }
}
