import Foundation

protocol HTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPClient: HTTPDataLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

struct AIExplanationService: Sendable {
    enum Error: LocalizedError, Equatable {
        case providerDisabled
        case invalidEndpoint(String)
        case missingModelName
        case missingOpenAIKey
        case requestFailed(String)
        case invalidResponseStatus(Int)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .providerDisabled:
                "AI is disabled in Preferences."
            case .invalidEndpoint(let endpoint):
                "The configured AI endpoint is invalid: \(endpoint)"
            case .missingModelName:
                "The configured AI model name is missing."
            case .missingOpenAIKey:
                "OpenAI is selected, but no API key is stored in Keychain."
            case .requestFailed(let message):
                message
            case .invalidResponseStatus(let statusCode):
                "The AI server responded with HTTP \(statusCode)."
            case .malformedResponse:
                "The AI response did not match the expected structured format."
            }
        }
    }

    private struct ChatCompletionsRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct ChatCompletionsResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct StructuredExplanationPayload: Decodable {
        let normalConditions: [String]
        let realRisks: [String]
        let expectedBehavior: [String]
        let unknownOrUnavailable: [String]
        let recommendedNextSteps: [String]
    }

    private let httpClient: any HTTPDataLoading

    init(httpClient: any HTTPDataLoading = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func explain(
        report: HealthReport? = nil,
        reportMarkdown: String,
        configuration: AIConfiguration,
        openAIAPIKey: String?
    ) async throws -> AIExplanation {
        switch configuration.provider {
        case .disabled:
            throw Error.providerDisabled
        case .lmStudio:
            let modelName = configuration.localModelName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelName.isEmpty else {
                throw Error.missingModelName
            }

            guard let url = URL(string: configuration.localBaseURL) else {
                throw Error.invalidEndpoint(configuration.localBaseURL)
            }

            return try await performRequest(
                url: url,
                modelName: modelName,
                report: report,
                reportMarkdown: reportMarkdown,
                configuration: configuration,
                authorizationHeader: nil,
                provider: .lmStudio,
                transportErrorLabel: "LM Studio server could not be reached at \(configuration.localBaseURL)."
            )
        case .ollama:
            let modelName = configuration.ollamaModelName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelName.isEmpty else {
                throw Error.missingModelName
            }

            guard let url = ollamaChatCompletionsURL(from: configuration.ollamaBaseURL) else {
                throw Error.invalidEndpoint(configuration.ollamaBaseURL)
            }

            return try await performRequest(
                url: url,
                modelName: modelName,
                report: report,
                reportMarkdown: reportMarkdown,
                configuration: configuration,
                authorizationHeader: nil,
                provider: .ollama,
                transportErrorLabel: "Ollama could not be reached at \(configuration.ollamaBaseURL)."
            )
        case .openAI:
            let modelName = configuration.openAIModelName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelName.isEmpty else {
                throw Error.missingModelName
            }

            guard
                let openAIAPIKey,
                !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw Error.missingOpenAIKey
            }

            guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                throw Error.invalidEndpoint("https://api.openai.com/v1/chat/completions")
            }

            return try await performRequest(
                url: url,
                modelName: modelName,
                report: report,
                reportMarkdown: reportMarkdown,
                configuration: configuration,
                authorizationHeader: "Bearer \(openAIAPIKey)",
                provider: .openAI,
                transportErrorLabel: "OpenAI could not be reached with the current network settings."
            )
        }
    }

    private func performRequest(
        url: URL,
        modelName: String,
        report: HealthReport?,
        reportMarkdown: String,
        configuration: AIConfiguration,
        authorizationHeader: String?,
        provider: AIProvider,
        transportErrorLabel: String
    ) async throws -> AIExplanation {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        let prompt = """
        You are explaining an existing Mac health report.
        Use only facts already present in the report or in the deterministic guidance message.
        Do not invent new findings.
        Do not recommend destructive actions unless they already appear in the report recommendations.
        Mention uncertainty when the report says Unknown or unavailable.
        Distinguish carefully between normal conditions, real risks, expected behavior, and unknown or unavailable data.
        Do not treat Unknown or unavailable data as healthy.
        Do not describe an item as a real risk unless the report explicitly flags it as a warning or critical issue, or explicitly says that a security protection is disabled.
        Treat point-in-time process activity, background items, LaunchAgents, KeepAlive agents, login items, caches, Trash contents, old downloads, large files, and missing maintenance history as expected or informational unless the report separately flags them as an issue or recommendation.
        If one control is the main reason for a low score, explain that specific control instead of spreading alarm to unrelated categories.
        Write five short sections with these exact headings:
        Normal Conditions
        Real Risks
        Expected Behavior
        Unknown or Unavailable
        Recommended Next Steps
        Base the Recommended Next Steps section only on deterministic report recommendations that already exist.
        Return only a JSON object with exactly these keys:
        normalConditions
        realRisks
        expectedBehavior
        unknownOrUnavailable
        recommendedNextSteps
        Each value must be an array of short complete sentences.
        Use [] for an empty section.
        Do not wrap the JSON in markdown fences.
        """

        let payload = ChatCompletionsRequest(
            model: modelName,
            messages: requestMessages(
                prompt: prompt,
                report: report,
                reportMarkdown: reportMarkdown
            ),
            temperature: 0.2
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await httpClient.data(for: request)
        } catch {
            throw Error.requestFailed("\(transportErrorLabel) \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.malformedResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw Error.invalidResponseStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ChatCompletionsResponse.self, from: responseData)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw Error.malformedResponse
        }

        let structuredExplanation = try decodeStructuredExplanation(from: content)

        return AIExplanation(
            provider: provider,
            disclaimer: "AI explanation is advisory. System facts come from local diagnostics.",
            normalConditions: structuredExplanation.normalConditions,
            realRisks: structuredExplanation.realRisks,
            expectedBehavior: structuredExplanation.expectedBehavior,
            unknownOrUnavailable: structuredExplanation.unknownOrUnavailable,
            recommendedNextSteps: structuredExplanation.recommendedNextSteps
        )
    }

    private func requestMessages(
        prompt: String,
        report: HealthReport?,
        reportMarkdown: String
    ) -> [ChatCompletionsRequest.Message] {
        var messages: [ChatCompletionsRequest.Message] = [
            .init(role: "system", content: prompt),
        ]

        if let report {
            messages.append(
                .init(
                    role: "user",
                    content: deterministicGuidance(for: report)
                )
            )
        }

        messages.append(
            .init(
                role: "user",
                content: """
                Local health report markdown:

                \(reportMarkdown)
                """
            )
        )

        return messages
    }

    private func deterministicGuidance(for report: HealthReport) -> String {
        let healthyCategories = [
            ("Storage", report.storage.status),
            ("Performance", report.performance.status),
            ("Security", report.security.status),
            ("Automation", report.automation.status),
        ]
        .filter { $0.1 == .healthy }
        .map { "\($0.0) is Healthy." }

        let unknownCategories = [
            ("Storage", report.storage.status),
            ("Performance", report.performance.status),
            ("Security", report.security.status),
            ("Automation", report.automation.status),
        ]
        .filter { $0.1 == .unknown }
        .map { "\($0.0) is Unknown." }

        let explicitIssues = allIssues(in: report)
            .sorted { lhs, rhs in
                if lhs.status.severityRank != rhs.status.severityRank {
                    return lhs.status.severityRank > rhs.status.severityRank
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { "[\($0.category.displayName) \($0.status.displayName)] \($0.title): \($0.explanation)" }

        let recommendations = report.recommendations.map {
            "[\($0.relatedCategory.displayName) \($0.riskLevel.rawValue)] \($0.title): \($0.explanation)"
        }

        var expectedBehaviorLines = [
            "Running apps can appear in CPU or memory snapshots without indicating a fault.",
            "Background items, LaunchAgents, KeepAlive agents, and login items are common on macOS. Presence or count alone is not a problem unless a separate issue says otherwise.",
            "Caches, Trash contents, old downloads, and large files are common observations. Treat them as review items only when the report also flags low space or adds a recommendation.",
        ]

        if !report.performance.topCPUProcesses.isEmpty || !report.performance.topMemoryProcesses.isEmpty {
            expectedBehaviorLines.append("This report includes point-in-time process snapshots. High usage in a single snapshot is observational unless a performance issue is also flagged.")
        }

        if !report.automation.keepAliveAgentLabels.isEmpty {
            expectedBehaviorLines.append("\(report.automation.keepAliveAgentLabels.count) KeepAlive agent(s) were observed. Presence alone is expected behavior; only broken plists, missing executables, stale log paths, or explicit issues should be treated as risk.")
        }

        if report.storage.trashSizeBytes != nil || report.storage.cachesSizeBytes != nil || !report.storage.oldDownloads.isEmpty || !report.storage.largeFiles.isEmpty {
            expectedBehaviorLines.append("Storage review items were observed. Old downloads, Trash contents, caches, and large files are not failures by themselves.")
        }

        if report.maintenanceActions.isEmpty {
            expectedBehaviorLines.append("No maintenance actions recorded yet is neutral history, not a fault.")
        }

        return """
        Deterministic guidance from local diagnostics. Treat this guidance as authoritative when deciding what is normal, risky, expected, or unknown.

        Healthy or normal categories:
        \(bulletList(from: healthyCategories, emptyFallback: "None explicitly marked Healthy."))

        Explicit warning or critical issues:
        \(bulletList(from: explicitIssues, emptyFallback: "No explicit warning or critical issues were flagged."))

        Existing deterministic recommendations:
        \(bulletList(from: recommendations, emptyFallback: "No deterministic recommendations are present."))

        Unknown or unavailable categories:
        \(bulletList(from: unknownCategories, emptyFallback: "No categories are currently Unknown."))

        Expected behavior that should not be escalated by itself:
        \(bulletList(from: expectedBehaviorLines, emptyFallback: "No additional expected-behavior notes."))
        """
    }

    private func decodeStructuredExplanation(from content: String) throws -> StructuredExplanationPayload {
        let jsonString = extractedJSONObjectString(from: content) ?? content

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw Error.malformedResponse
        }

        let decoder = JSONDecoder()

        do {
            let decoded = try decoder.decode(StructuredExplanationPayload.self, from: jsonData)
            return StructuredExplanationPayload(
                normalConditions: normalizedItems(from: decoded.normalConditions),
                realRisks: normalizedItems(from: decoded.realRisks),
                expectedBehavior: normalizedItems(from: decoded.expectedBehavior),
                unknownOrUnavailable: normalizedItems(from: decoded.unknownOrUnavailable),
                recommendedNextSteps: normalizedItems(from: decoded.recommendedNextSteps)
            )
        } catch {
            throw Error.malformedResponse
        }
    }

    private func extractedJSONObjectString(from content: String) -> String? {
        guard let startIndex = content.firstIndex(of: "{"), let endIndex = content.lastIndex(of: "}") else {
            return nil
        }

        guard startIndex <= endIndex else {
            return nil
        }

        return String(content[startIndex...endIndex])
    }

    private func normalizedItems(from items: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            if seen.insert(trimmed).inserted {
                normalized.append(trimmed)
            }
        }

        return normalized
    }

    private func allIssues(in report: HealthReport) -> [HealthIssue] {
        report.storage.issues
            + report.performance.issues
            + report.security.issues
            + report.automation.issues
    }

    private func bulletList(from items: [String], emptyFallback: String) -> String {
        guard !items.isEmpty else {
            return "- \(emptyFallback)"
        }

        return items.map { "- \($0)" }.joined(separator: "\n")
    }

    private func ollamaChatCompletionsURL(from baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath == "v1/chat/completions" {
            return components.url
        }

        let basePath = normalizedPath.isEmpty ? "" : "/" + normalizedPath
        components.path = basePath + "/v1/chat/completions"
        return components.url
    }
}
