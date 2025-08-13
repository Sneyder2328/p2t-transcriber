import Foundation

public enum EventStreamHeaderValue {
    case string(String)
}

public struct EventStreamMessage {
    public let headers: [String: EventStreamHeaderValue]
    public let payload: Data
}

public final class AWSEventStreamCodec {
    private enum HeaderType: UInt8 { case string = 7 }

    public static func encode(headers: [String: EventStreamHeaderValue], payload: Data) -> Data {
        var headersData = Data()
        for (key, value) in headers {
            guard let keyData = key.data(using: .utf8), keyData.count <= 255 else { continue }
            headersData.append(UInt8(keyData.count))
            headersData.append(keyData)
            switch value {
            case .string(let s):
                headersData.append(HeaderType.string.rawValue)
                let strData = s.data(using: .utf8) ?? Data()
                headersData.append(contentsOf: withUnsafeBytes(of: UInt16(strData.count).bigEndian, Array.init))
                headersData.append(strData)
            }
        }

        let headersLen = UInt32(headersData.count)
        let totalLen = UInt32(4 + 4 + 4) + headersLen + UInt32(payload.count) + UInt32(4)

        var out = Data()
        out.append(contentsOf: withUnsafeBytes(of: totalLen.bigEndian, Array.init))
        out.append(contentsOf: withUnsafeBytes(of: headersLen.bigEndian, Array.init))
        let preludeCRC = crc32(out)
        out.append(contentsOf: withUnsafeBytes(of: preludeCRC.bigEndian, Array.init))
        out.append(headersData)
        out.append(payload)
        let messageCRC = crc32(out)
        out.append(contentsOf: withUnsafeBytes(of: messageCRC.bigEndian, Array.init))
        return out
    }

    public static func decodeAvailable(from buffer: inout Data) -> [EventStreamMessage] {
        var messages: [EventStreamMessage] = []
        var offset = 0
        while true {
            guard buffer.count - offset >= 16 else { break }
            let totalLen = Int(readUInt32BE(buffer, offset: offset))
            let headersLen = Int(readUInt32BE(buffer, offset: offset + 4))
            guard totalLen >= 16 && headersLen >= 0 else { break }
            guard buffer.count - offset >= totalLen else { break }

            let headersStart = offset + 12
            let payloadStart = headersStart + headersLen
            let payloadLen = max(0, totalLen - 12 - headersLen - 4)
            guard headersStart >= 0 && payloadStart >= 0 && payloadLen >= 0 else { break }
            guard headersStart + headersLen <= buffer.count && payloadStart + payloadLen <= buffer.count else { break }

            guard let headersSlice = slice(buffer, offset: headersStart, length: headersLen) else { break }
            guard let payload = slice(buffer, offset: payloadStart, length: payloadLen) else { break }

            let headers = decodeHeaders(headersSlice)
            messages.append(EventStreamMessage(headers: headers, payload: payload))
            offset += totalLen
        }
        if offset > 0 { buffer.removeFirst(offset) }
        return messages
    }

    private static func decodeHeaders(_ data: Data) -> [String: EventStreamHeaderValue] {
        var headers: [String: EventStreamHeaderValue] = [:]
        var i = 0
        while i < data.count {
            guard i + 1 <= data.count else { break }
            let keyLen = Int(data[i]); i += 1
            guard i + keyLen <= data.count else { break }
            let keyData = slice(data, offset: i, length: keyLen) ?? Data()
            let key = String(data: keyData, encoding: .utf8) ?? ""
            i += keyLen
            guard i + 1 <= data.count else { break }
            let type = data[i]; i += 1
            switch type {
            case HeaderType.string.rawValue:
                guard i + 2 <= data.count else { break }
                let len = Int(readUInt16BE(data, offset: i)); i += 2
                guard i + len <= data.count else { break }
                let valueData = slice(data, offset: i, length: len) ?? Data()
                let value = String(data: valueData, encoding: .utf8) ?? ""
                i += len
                headers[key] = .string(value)
            default:
                return headers
            }
        }
        return headers
    }

    private static func slice(_ data: Data, offset: Int, length: Int) -> Data? {
        guard offset >= 0 && length >= 0 && offset + length <= data.count else { return nil }
        return data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            return Data(bytes: base + offset, count: length)
        }
    }

    private static func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        return data.withUnsafeBytes { raw -> UInt32 in
            guard offset + 4 <= raw.count else { return 0 }
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            let p = base + offset
            let b0 = UInt32(p[0])
            let b1 = UInt32(p[1])
            let b2 = UInt32(p[2])
            let b3 = UInt32(p[3])
            return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }
    }

    private static func readUInt16BE(_ data: Data, offset: Int) -> UInt16 {
        return data.withUnsafeBytes { raw -> UInt16 in
            guard offset + 2 <= raw.count else { return 0 }
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            let p = base + offset
            let b0 = UInt16(p[0])
            let b1 = UInt16(p[1])
            return (b0 << 8) | b1
        }
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for b in buf { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFFFFFF
    }
}
