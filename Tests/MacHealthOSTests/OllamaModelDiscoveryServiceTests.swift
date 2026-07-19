import Foundation
import Testing
@testable import MacHealthOS

@Test func ollamaDiscoveryServiceParsesLiveModels() async throws {
    let responseURL = try #require(URL(string: "http://localhost:11434/api/tags"))
    let httpResponse = try #require(
        HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
    )
    let service = OllamaModelDiscoveryService(
        httpClient: StubOllamaHTTPClient(
            response: .success(
                Data(
                    #"""
                    {
                      "models": [
                        {
                          "name": "mistral:latest",
                          "size": 4372824384,
                          "details": {
                            "family": "llama",
                            "parameter_size": "7.2B",
                            "quantization_level": "Q4_K_M"
                          }
                        },
                        {
                          "name": "llama3.2:latest",
                          "size": 2019393189,
                          "details": {
                            "family": "llama",
                            "parameter_size": "3.2B",
                            "quantization_level": "Q4_K_M"
                          }
                        }
                      ]
                    }
                    """#.utf8
                ),
                httpResponse
            )
        )
    )

    let models = try await service.fetchModels(
        baseURL: "http://localhost:11434",
        timeoutSeconds: 5
    )

    #expect(models.count == 2)
    #expect(models[0].name == "mistral:latest")
    #expect(models[0].sizeBytes == 4_372_824_384)
    #expect(models[0].family == "llama")
    #expect(models[1].parameterSize == "3.2B")
}

@Test func ollamaDiscoveryServiceReturnsClearFailure() async throws {
    let service = OllamaModelDiscoveryService(
        httpClient: StubOllamaHTTPClient(
            response: .failure(URLError(.cannotConnectToHost))
        )
    )

    do {
        _ = try await service.fetchModels(
            baseURL: "http://localhost:11434",
            timeoutSeconds: 5
        )
        Issue.record("Expected Ollama discovery failure to be surfaced.")
    } catch let error as OllamaModelDiscoveryService.Error {
        guard case .requestFailed(let message) = error else {
            Issue.record("Unexpected Ollama discovery error: \(error)")
            return
        }

        #expect(message.contains("Ollama could not be reached at http://localhost:11434."))
        #expect(message.contains("NSURLErrorDomain error -1004"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

private struct StubOllamaHTTPClient: HTTPDataLoading {
    enum Response {
        case success(Data, URLResponse)
        case failure(Swift.Error)
    }

    var response: Response

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        switch response {
        case .success(let data, let urlResponse):
            return (data, urlResponse)
        case .failure(let error):
            throw error
        }
    }
}
