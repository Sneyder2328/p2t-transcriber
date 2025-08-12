import Foundation
import CryptoKit

struct AwsCredentials {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?
}

final class TranscribeSigner {
    let region: String
    let service = "transcribe"

    init(region: String) {
        self.region = region
    }

    func presignWebsocketUrl(
        credentials: AwsCredentials,
        languageCode: String,
        sampleRate: Int = 16000,
        mediaEncoding: String = "pcm",
        extraParams: [String: String] = [:]
    ) -> URL? {
        let hostWithPort = "transcribestreaming." + region + ".amazonaws.com:8443"
        let endpoint = "wss://" + hostWithPort + "/stream-transcription-websocket"

        var query: [String: String] = [
            "language-code": languageCode,
            "media-encoding": mediaEncoding,
            "sample-rate": String(sampleRate),
            "X-Amz-Content-Sha256": "UNSIGNED-PAYLOAD"
        ]
        for (k, v) in extraParams { query[k] = v }

        let now = Date()
        let amzDate = Self.timestamp(now)
        let dateScope = String(amzDate.prefix(8))
        let credentialScope = "\(dateScope)/\(region)/\(service)/aws4_request"

        query["X-Amz-Algorithm"] = "AWS4-HMAC-SHA256"
        query["X-Amz-Credential"] = "\(credentials.accessKeyId)/\(credentialScope)"
        query["X-Amz-Date"] = amzDate
        query["X-Amz-Expires"] = "300"
        query["X-Amz-SignedHeaders"] = "host"
        if let token = credentials.sessionToken { query["X-Amz-Security-Token"] = token }

        let canonicalQuery = Self.canonicalQueryString(query, encodeValues: true)
        let canonicalHeaders = "host:\(hostWithPort)\n"
        let signedHeaders = "host"
        let canonicalRequest = [
            "GET",
            "/stream-transcription-websocket",
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")

        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            Self.hexSha256(canonicalRequest)
        ].joined(separator: "\n")

        let signingKey = Self.signingKey(secretKey: credentials.secretAccessKey, date: dateScope, region: region, service: service)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: signingKey))
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()

        var finalQueryItems = query
        finalQueryItems["X-Amz-Signature"] = signatureHex
        let finalUrlString = endpoint + "?" + Self.canonicalQueryString(finalQueryItems, encodeValues: true)
        return URL(string: finalUrlString)
    }

    private static func signingKey(secretKey: String, date: String, region: String, service: String) -> Data {
        let kDate = Self.hmac("AWS4" + secretKey, date)
        let kRegion = Self.hmacData(kDate, region)
        let kService = Self.hmacData(kRegion, service)
        let kSigning = Self.hmacData(kService, "aws4_request")
        return kSigning
    }

    private static func hmac(_ key: String, _ data: String) -> Data {
        let keyData = Data(key.utf8)
        return hmacData(keyData, data)
    }

    private static func hmacData(_ key: Data, _ data: String) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: SymmetricKey(data: key))
        return Data(mac)
    }

    private static func canonicalQueryString(_ params: [String: String], encodeValues: Bool = false) -> String {
        params
            .map { (Self.urlEncode($0.key), encodeValues ? Self.urlEncode($0.value) : $0.value) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0)=\($1)" }
            .joined(separator: "&")
    }

    private static func urlEncode(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private static func hexSha256(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }
}
