import Foundation

struct PreferencesStore: Sendable {
    private enum Keys {
        static let aiConfiguration = "ai_configuration"
    }

    let suiteName: String?

    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    func loadAIConfiguration() -> AIConfiguration {
        guard
            let data = defaults.data(forKey: Keys.aiConfiguration),
            let configuration = try? JSONDecoder().decode(AIConfiguration.self, from: data)
        else {
            return .default
        }

        return configuration
    }

    func saveAIConfiguration(_ configuration: AIConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }

        defaults.set(data, forKey: Keys.aiConfiguration)
    }

    private var defaults: UserDefaults {
        if let suiteName, let userDefaults = UserDefaults(suiteName: suiteName) {
            return userDefaults
        }

        return .standard
    }
}
