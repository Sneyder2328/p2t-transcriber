import Foundation
import Security

final class CredentialsStore {
    static let shared = CredentialsStore()

    private let service = "com.sneyder.p2t.credentials"

    func save(accessKeyId: String, secretAccessKey: String, sessionToken: String?) {
        let dict: [String: String] = [
            "accessKeyId": accessKeyId,
            "secretAccessKey": secretAccessKey,
            "sessionToken": sessionToken ?? ""
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict, options: [])
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "aws",
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func load() -> AwsCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "aws",
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        guard let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else { return nil }
        let accessKeyId = dict["accessKeyId"] ?? ""
        let secretAccessKey = dict["secretAccessKey"] ?? ""
        let sessionToken = dict["sessionToken"].flatMap { $0.isEmpty ? nil : $0 }
        guard !accessKeyId.isEmpty, !secretAccessKey.isEmpty else { return nil }
        return AwsCredentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken)
    }
}
