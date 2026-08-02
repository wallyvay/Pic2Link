import Foundation
import Security

protocol CredentialStoring {
    func data(for account: String) throws -> Data?
    func set(_ data: Data, for account: String) throws
    func remove(for account: String) throws
}

enum KeychainServiceError: LocalizedError {
    case unexpectedData
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return L10n.tr("error.keychainUnexpectedData")
        case .status(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? L10n.tr("error.keychainStatus", status)
        }
    }
}

final class KeychainService: CredentialStoring {
    static let shared = KeychainService()

    private let service: String

    init(service: String = "Amanoya.Pic2Link.profileCredentials") {
        self.service = service
    }

    func data(for account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainServiceError.unexpectedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainServiceError.status(status)
        }
    }

    func set(_ data: Data, for account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )

        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainServiceError.status(addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainServiceError.status(status)
        }
    }

    func remove(for account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.status(status)
        }
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false
        ]
    }
}
