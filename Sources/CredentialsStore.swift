import Foundation
import Security

final class CredentialsStore {
    static let shared = CredentialsStore()

    private let service = "com.sneyder.p2t.credentials" 

    @discardableResult
    func save(accessKeyId: String, secretAccessKey: String, sessionToken: String?) -> Bool {
        let dict: [String: String] = [
            "accessKeyId": accessKeyId,
            "secretAccessKey": secretAccessKey,
            "sessionToken": sessionToken ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else {
            print("Keychain save error: JSON encode failed")
            return false
        }

        // Delete any existing item first
        let matchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "aws"
        ]
        SecItemDelete(matchQuery as CFDictionary)

        var addQuery: [String: Any] = matchQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrLabel as String] = "P2T AWS Credentials"
        // Do NOT set kSecUseDataProtectionKeychain or kSecAttrAccessible on macOS to avoid entitlement -34018

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            print("Keychain save error (status=\(status)): \(message)")
            return false
        }
        return true
    }

    func load() -> AwsCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "aws",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
                print("Keychain load error (status=\(status)): \(message)")
            }
            return nil
        }
        guard let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else { return nil }
        let accessKeyId = dict["accessKeyId"] ?? ""
        let secretAccessKey = dict["secretAccessKey"] ?? ""
        let sessionToken = dict["sessionToken"].flatMap { $0.isEmpty ? nil : $0 }
        guard !accessKeyId.isEmpty, !secretAccessKey.isEmpty else { return nil }
        return AwsCredentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken)
    }
}
