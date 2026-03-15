import Foundation
import Security

protocol SSHConnectionCredentialStore {
    func password(for hostID: String) throws -> String?
    func setPassword(_ password: String, for hostID: String) throws
    func removePassword(for hostID: String) throws
}

enum SSHConnectionCredentialStoreError: LocalizedError {
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            "Keychain returned an unexpected password payload."
        case .unhandledStatus(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }
}

struct KeychainSSHConnectionCredentialStore: SSHConnectionCredentialStore {
    static let service = "com.mitchellh.ghostty.ssh"

    func password(for hostID: String) throws -> String? {
        let query = baseQuery(for: hostID).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, new in new }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                throw SSHConnectionCredentialStoreError.unexpectedData
            }
            return password

        case errSecItemNotFound:
            return nil

        default:
            throw SSHConnectionCredentialStoreError.unhandledStatus(status)
        }
    }

    func setPassword(_ password: String, for hostID: String) throws {
        try removePassword(for: hostID)

        var query = baseQuery(for: hostID)
        query[kSecValueData as String] = Data(password.utf8)
        query[kSecAttrLabel as String] = "Ghostty SSH Password"

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SSHConnectionCredentialStoreError.unhandledStatus(status)
        }
    }

    func removePassword(for hostID: String) throws {
        let status = SecItemDelete(baseQuery(for: hostID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SSHConnectionCredentialStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(for hostID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: hostID,
        ]
    }
}
