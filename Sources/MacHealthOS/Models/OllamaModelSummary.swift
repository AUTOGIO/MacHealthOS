import Foundation

struct OllamaModelSummary: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let sizeBytes: Int64?
    let family: String?
    let parameterSize: String?
    let quantizationLevel: String?

    init(
        id: String? = nil,
        name: String,
        sizeBytes: Int64? = nil,
        family: String? = nil,
        parameterSize: String? = nil,
        quantizationLevel: String? = nil
    ) {
        self.id = id ?? name
        self.name = name
        self.sizeBytes = sizeBytes
        self.family = family
        self.parameterSize = parameterSize
        self.quantizationLevel = quantizationLevel
    }
}
