import Foundation

struct OllamaModelDiscoveryService: Sendable {
    enum Error: LocalizedError, Equatable {
        case invalidEndpoint(String)
        case requestFailed(String)
        case invalidResponseStatus(Int)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint(let endpoint):
                "The configured Ollama endpoint is invalid: \(endpoint)"
            case .requestFailed(let message):
                message
            case .invalidResponseStatus(let statusCode):
                "Ollama responded with HTTP \(statusCode)."
            case .malformedResponse:
                "The Ollama model list could not be understood."
            }
        }
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable {
            struct Details: Decodable {
                let family: String?
                let parameterSize: String?
                let quantizationLevel: String?

                private enum CodingKeys: String, CodingKey {
                    case family
                    case parameterSize = "parameter_size"
                    case quantizationLevel = "quantization_level"
                }
            }

            let name: String
            let size: Int64?
            let details: Details?
        }

        let models: [Model]
    }

    private let httpClient: any HTTPDataLoading

    init(httpClient: any HTTPDataLoading = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func fetchModels(
        baseURL: String,
        timeoutSeconds: Double
    ) async throws -> [OllamaModelSummary] {
        guard let url = resolvedTagsURL(from: baseURL) else {
            throw Error.invalidEndpoint(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await httpClient.data(for: request)
        } catch {
            throw Error.requestFailed("Ollama could not be reached at \(baseURL). \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.malformedResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw Error.invalidResponseStatus(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(TagsResponse.self, from: responseData)
        return decoded.models.map { model in
            OllamaModelSummary(
                name: model.name,
                sizeBytes: model.size,
                family: model.details?.family,
                parameterSize: model.details?.parameterSize,
                quantizationLevel: model.details?.quantizationLevel
            )
        }
    }

    private func resolvedTagsURL(from baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath == "api/tags" {
            return components.url
        }

        let basePath: String
        if normalizedPath == "v1/chat/completions" {
            basePath = ""
        } else {
            basePath = normalizedPath.isEmpty ? "" : "/" + normalizedPath
        }

        components.path = basePath + "/api/tags"
        return components.url
    }
}
