import Foundation
import Security

protocol SecretStoring: Sendable {
    func loadSecret(account: String) throws -> String?
    func saveSecret(_ secret: String, account: String) throws
    func deleteSecret(account: String) throws
}

struct KeychainStore: SecretStoring {
    enum Error: LocalizedError {
        case unexpectedStatus(OSStatus)
        case invalidEncoding

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                "Keychain returned status \(status)."
            case .invalidEncoding:
                "The stored Keychain item could not be decoded."
            }
        }
    }

    let serviceName: String

    init(serviceName: String = "MacHealthOS") {
        self.serviceName = serviceName
    }

    func loadSecret(account: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
                throw Error.invalidEncoding
            }
            return secret
        case errSecItemNotFound:
            return nil
        default:
            throw Error.unexpectedStatus(status)
        }
    }

    func saveSecret(_ secret: String, account: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw Error.invalidEncoding
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: account,
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw Error.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw Error.unexpectedStatus(addStatus)
        }
    }

    func deleteSecret(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.unexpectedStatus(status)
        }
    }
}
