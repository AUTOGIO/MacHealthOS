import Foundation
import Testing
@testable import MacHealthOS

@Test func aiExplanationServiceRejectsDisabledProvider() async throws {
    let service = AIExplanationService(httpClient: StubHTTPClient())

    await #expect(throws: AIExplanationService.Error.providerDisabled) {
        try await service.explain(
            reportMarkdown: "# Report",
            configuration: .default,
            openAIAPIKey: nil
        )
    }
}

@Test func aiExplanationServiceReturnsClearLMStudioFailure() async throws {
    let service = AIExplanationService(
        httpClient: StubHTTPClient(
            response: .failure(URLError(.cannotConnectToHost))
        )
    )

    let configuration = AIConfiguration(
        provider: .lmStudio,
        localBaseURL: "http://localhost:1234/v1/chat/completions",
        localModelName: "local-model",
        ollamaBaseURL: "http://localhost:11434",
        ollamaModelName: "llama3.2:latest",
        timeoutSeconds: 5,
        openAIModelName: "gpt-4.1-mini"
    )

    do {
        _ = try await service.explain(
            reportMarkdown: "# Report",
            configuration: configuration,
            openAIAPIKey: nil
        )
        Issue.record("Expected LM Studio connection failure to be surfaced.")
    } catch let error as AIExplanationService.Error {
        guard case .requestFailed(let message) = error else {
            Issue.record("Unexpected AIExplanationService error: \(error)")
            return
        }

        #expect(message.contains("LM Studio server could not be reached at http://localhost:1234/v1/chat/completions."))
        #expect(message.contains("NSURLErrorDomain error -1004"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func aiExplanationServiceBuildsOllamaCompatibleRequest() async throws {
    let responseURL = try #require(URL(string: "http://localhost:11434/v1/chat/completions"))
    let httpResponse = try #require(
        HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
    )
    let client = RecordingHTTPClient(
        response: .success(
            Data(#"{"choices":[{"message":{"content":"{\"normalConditions\":[\"Performance is healthy.\"],\"realRisks\":[\"FileVault is disabled.\"],\"expectedBehavior\":[\"Background items are present.\"],\"unknownOrUnavailable\":[],\"recommendedNextSteps\":[\"Review always-on background items.\"]}"}}]}"#.utf8),
            httpResponse
        )
    )
    let service = AIExplanationService(httpClient: client)

    let configuration = AIConfiguration(
        provider: .ollama,
        localBaseURL: "http://localhost:1234/v1/chat/completions",
        localModelName: "local-model",
        ollamaBaseURL: "http://localhost:11434",
        ollamaModelName: "llama3.2:latest",
        timeoutSeconds: 5,
        openAIModelName: "gpt-4.1-mini"
    )

    let explanation = try await service.explain(
        reportMarkdown: "# Report",
        configuration: configuration,
        openAIAPIKey: nil
    )

    #expect(explanation.provider == .ollama)
    #expect(explanation.normalConditions == ["Performance is healthy."])
    #expect(explanation.realRisks == ["FileVault is disabled."])
    #expect(explanation.expectedBehavior == ["Background items are present."])
    #expect(explanation.unknownOrUnavailable.isEmpty)
    #expect(explanation.recommendedNextSteps == ["Review always-on background items."])

    let request = await client.recordedRequest()
    #expect(request?.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
}

@Test func aiExplanationServiceSendsRiskClassificationGuidance() async throws {
    let responseURL = try #require(URL(string: "http://localhost:11434/v1/chat/completions"))
    let httpResponse = try #require(
        HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
    )
    let client = RecordingHTTPClient(
        response: .success(
            Data(#"{"choices":[{"message":{"content":"{\"normalConditions\":[\"Performance is healthy.\"],\"realRisks\":[\"FileVault is disabled.\"],\"expectedBehavior\":[\"KeepAlive agents are present but not automatically risky.\"],\"unknownOrUnavailable\":[],\"recommendedNextSteps\":[\"Review always-on background items.\"]}"}}]}"#.utf8),
            httpResponse
        )
    )
    let service = AIExplanationService(httpClient: client)

    let configuration = AIConfiguration(
        provider: .ollama,
        localBaseURL: "http://localhost:1234/v1/chat/completions",
        localModelName: "local-model",
        ollamaBaseURL: "http://localhost:11434",
        ollamaModelName: "llama3.2:latest",
        timeoutSeconds: 5,
        openAIModelName: "gpt-4.1-mini"
    )

    let report = HealthReport(
        generatedAt: Date(timeIntervalSince1970: 1_782_466_469.573),
        machine: MachineProfile(
            machineName: "Eduardo's MacBook Air",
            macOSVersion: "Version 26.6 (Build 25G5043d)",
            hardwareArchitecture: "arm64"
        ),
        storage: StorageDiagnostics(
            status: .warning,
            trashSizeBytes: 200_000_000,
            cachesSizeBytes: 400_000_000,
            oldDownloads: [
                .init(
                    path: "/Users/eduardofgiovannini/Downloads/old-file.zip",
                    sizeBytes: 25_000_000,
                    contentModificationDate: Date(timeIntervalSince1970: 1_780_000_000)
                )
            ]
        ),
        performance: PerformanceDiagnostics(
            status: .healthy,
            topCPUProcesses: [
                .init(
                    pid: 100,
                    command: "WindowServer",
                    cpuPercent: 12.5,
                    memoryPercent: 1.1,
                    residentMemoryBytes: 250_000_000
                )
            ]
        ),
        security: SecurityDiagnostics(
            status: .critical,
            fileVaultEnabled: false,
            issues: [
                HealthIssue(
                    category: .security,
                    status: .critical,
                    title: "FileVault is disabled",
                    explanation: "Disk encryption is currently turned off."
                )
            ]
        ),
        automation: AutomationDiagnostics(
            status: .warning,
            keepAliveAgentLabels: [
                "com.example.agent1",
                "com.example.agent2",
                "com.example.agent3",
                "com.example.agent4",
                "com.example.agent5",
                "com.example.agent6",
                "com.example.agent7",
                "com.example.agent8",
            ]
        ),
        recommendations: [
            MaintenanceRecommendation(
                title: "Review always-on background items",
                explanation: "Several always-on items are enabled.",
                riskLevel: .review,
                estimatedImpact: "May reduce background load.",
                reversibility: "Manual and reversible.",
                relatedCategory: .automation
            )
        ]
    )

    _ = try await service.explain(
        report: report,
        reportMarkdown: "# Report",
        configuration: configuration,
        openAIAPIKey: nil
    )

    let request = try #require(await client.recordedRequest())
    let body = try #require(request.httpBody)
    let payload = try JSONDecoder().decode(CapturedChatCompletionsRequest.self, from: body)

    #expect(payload.messages.count == 3)
    #expect(payload.messages[0].role == "system")
    #expect(payload.messages[0].content.contains("Return only a JSON object"))
    #expect(payload.messages[0].content.contains("normalConditions"))
    #expect(payload.messages[0].content.contains("realRisks"))
    #expect(payload.messages[0].content.contains("expectedBehavior"))
    #expect(payload.messages[0].content.contains("unknownOrUnavailable"))
    #expect(payload.messages[0].content.contains("recommendedNextSteps"))

    #expect(payload.messages[1].content.contains("Deterministic guidance from local diagnostics."))
    #expect(payload.messages[1].content.contains("Performance is Healthy."))
    #expect(payload.messages[1].content.contains("FileVault is disabled"))
    #expect(payload.messages[1].content.contains("8 KeepAlive agent(s) were observed. Presence alone is expected behavior"))
    #expect(payload.messages[1].content.contains("Storage review items were observed. Old downloads, Trash contents, caches, and large files are not failures by themselves."))
    #expect(payload.messages[1].content.contains("No maintenance actions recorded yet is neutral history, not a fault."))
}

@Test func aiExplanationServiceAcceptsJSONWrappedInMarkdownFences() async throws {
    let responseURL = try #require(URL(string: "http://localhost:11434/v1/chat/completions"))
    let httpResponse = try #require(
        HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
    )
    let client = RecordingHTTPClient(
        response: .success(
            Data(#"{"choices":[{"message":{"content":"```json\n{\"normalConditions\":[\"Performance is healthy.\"],\"realRisks\":[],\"expectedBehavior\":[\"Trash and caches are informational.\"],\"unknownOrUnavailable\":[\"Firewall state is unavailable.\"],\"recommendedNextSteps\":[]}\n```"}}]}"#.utf8),
            httpResponse
        )
    )
    let service = AIExplanationService(httpClient: client)

    let configuration = AIConfiguration(
        provider: .ollama,
        localBaseURL: "http://localhost:1234/v1/chat/completions",
        localModelName: "local-model",
        ollamaBaseURL: "http://localhost:11434",
        ollamaModelName: "llama3.2:latest",
        timeoutSeconds: 5,
        openAIModelName: "gpt-4.1-mini"
    )

    let explanation = try await service.explain(
        reportMarkdown: "# Report",
        configuration: configuration,
        openAIAPIKey: nil
    )

    #expect(explanation.normalConditions == ["Performance is healthy."])
    #expect(explanation.expectedBehavior == ["Trash and caches are informational."])
    #expect(explanation.unknownOrUnavailable == ["Firewall state is unavailable."])
}

@Test func aiExplanationServiceRejectsUnstructuredResponse() async throws {
    let responseURL = try #require(URL(string: "http://localhost:11434/v1/chat/completions"))
    let httpResponse = try #require(
        HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
    )
    let client = RecordingHTTPClient(
        response: .success(
            Data(#"{"choices":[{"message":{"content":"This Mac looks mostly fine."}}]}"#.utf8),
            httpResponse
        )
    )
    let service = AIExplanationService(httpClient: client)

    let configuration = AIConfiguration(
        provider: .ollama,
        localBaseURL: "http://localhost:1234/v1/chat/completions",
        localModelName: "local-model",
        ollamaBaseURL: "http://localhost:11434",
        ollamaModelName: "llama3.2:latest",
        timeoutSeconds: 5,
        openAIModelName: "gpt-4.1-mini"
    )

    await #expect(throws: AIExplanationService.Error.malformedResponse) {
        try await service.explain(
            reportMarkdown: "# Report",
            configuration: configuration,
            openAIAPIKey: nil
        )
    }
}

@Test func aiExplanationServiceRequiresOpenAIKeyWhenOpenAIIsSelected() async throws {
    let service = AIExplanationService(httpClient: StubHTTPClient())

    let configuration = AIConfiguration(
        provider: .openAI,
        localBaseURL: "http://localhost:1234/v1/chat/completions",
        localModelName: "local-model",
        ollamaBaseURL: "http://localhost:11434",
        ollamaModelName: "llama3.2:latest",
        timeoutSeconds: 5,
        openAIModelName: "gpt-4.1-mini"
    )

    await #expect(throws: AIExplanationService.Error.missingOpenAIKey) {
        try await service.explain(
            reportMarkdown: "# Report",
            configuration: configuration,
            openAIAPIKey: nil
        )
    }
}

private actor RecordingHTTPClient: HTTPDataLoading {
    enum Response {
        case success(Data, URLResponse)
        case failure(Swift.Error)
    }

    private let response: Response
    private var lastRequest: URLRequest?

    init(response: Response) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request

        switch response {
        case .success(let data, let urlResponse):
            return (data, urlResponse)
        case .failure(let error):
            throw error
        }
    }

    func recordedRequest() -> URLRequest? {
        lastRequest
    }
}

private struct CapturedChatCompletionsRequest: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct StubHTTPClient: HTTPDataLoading {
    enum Response {
        case success(Data, URLResponse)
        case failure(Swift.Error)
    }

    var response: Response?

    init(response: Response? = nil) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        switch response {
        case .success(let data, let urlResponse):
            (data, urlResponse)
        case .failure(let error):
            throw error
        case nil:
            throw URLError(.badServerResponse)
        }
    }
}
