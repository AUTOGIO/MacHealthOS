import Foundation
import Testing
@testable import MacHealthOS

@MainActor
@Test func appModelStartsWithUnknownStatus() async throws {
    let suiteName = UUID().uuidString
    defer {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    let model = AppModel(
        preferencesStore: PreferencesStore(suiteName: suiteName),
        keychainStore: EmptySecretStore()
    )

    #expect(model.healthScore == "Unknown")
    #expect(model.storageStatus == "Unknown")
    #expect(model.performanceStatus == "Unknown")
    #expect(model.securityStatus == "Unknown")
    #expect(model.automationStatus == "Unknown")
    #expect(model.latestScanTimestamp == nil)
    #expect(model.latestReportFiles == nil)
    #expect(model.aiProvider == AIProvider.disabled)
}

@Test func aiConfigurationDecodesOlderPayloadWithOllamaDefaults() throws {
    let legacyData = Data(
        #"""
        {
          "provider": "lmStudio",
          "localBaseURL": "http://localhost:1234/v1/chat/completions",
          "localModelName": "legacy-model",
          "timeoutSeconds": 15,
          "openAIModelName": "gpt-4.1-mini"
        }
        """#.utf8
    )

    let configuration = try JSONDecoder().decode(AIConfiguration.self, from: legacyData)

    #expect(configuration.provider == .lmStudio)
    #expect(configuration.localModelName == "legacy-model")
    #expect(configuration.ollamaBaseURL == "http://localhost:11434")
    #expect(configuration.ollamaModelName.isEmpty)
}

private struct EmptySecretStore: SecretStoring {
    func loadSecret(account: String) throws -> String? {
        nil
    }

    func saveSecret(_ secret: String, account: String) throws {}

    func deleteSecret(account: String) throws {}
}
