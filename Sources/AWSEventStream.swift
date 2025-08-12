import Foundation

public enum EventStreamHeaderValue {
    case string(String)
}

public struct EventStreamMessage {
    public let headers: [String: EventStreamHeaderValue]
    public let payload: Data
}

public final class AWSEventStreamCodec {
    private enum HeaderType: UInt8 { case boolTrue = 0, boolFalse = 1, byte = 2, int16 = 3, int32 = 4, int64 = 5, byteArray = 6, string = 7, timestamp = 8, uuid = 9 }

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

    public static func decodeAll(from data: Data) -> [EventStreamMessage] {
        var messages: [EventStreamMessage] = []
        var offset = 0
        while offset + 16 <= data.count {
            let totalLen = Int(readUInt32BE(data, offset: offset)); offset += 4
            let headersLen = Int(readUInt32BE(data, offset: offset)); offset += 4
            offset += 4 // prelude CRC
            guard offset + headersLen <= data.count else { break }
            let headersSlice = data.subdata(in: offset..<(offset + headersLen)); offset += headersLen
            let payloadLen = max(0, totalLen - 12 - headersLen - 4)
            guard offset + payloadLen + 4 <= data.count else { break }
            let payload = data.subdata(in: offset..<(offset + payloadLen)); offset += payloadLen
            offset += 4 // message CRC

            let headers = decodeHeaders(headersSlice)
            messages.append(EventStreamMessage(headers: headers, payload: payload))
        }
        return messages
    }

    private static func decodeHeaders(_ data: Data) -> [String: EventStreamHeaderValue] {
        var headers: [String: EventStreamHeaderValue] = [:]
        var i = 0
        while i < data.count {
            let keyLen = Int(data[i]); i += 1
            guard i + keyLen <= data.count else { break }
            let key = String(data: data.subdata(in: i..<(i + keyLen)), encoding: .utf8) ?? ""
            i += keyLen
            guard i < data.count else { break }
            let type = data[i]; i += 1
            switch type {
            case 7: // string
                guard i + 2 <= data.count else { break }
                let len = Int(readUInt16BE(data, offset: i)); i += 2
                guard i + len <= data.count else { break }
                let value = String(data: data.subdata(in: i..<(i + len)), encoding: .utf8) ?? ""
                i += len
                headers[key] = .string(value)
            default:
                return headers
            }
        }
        return headers
    }

    private static func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        let slice = data.subdata(in: offset..<(offset + 4))
        return slice.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
    private static func readUInt16BE(_ data: Data, offset: Int) -> UInt16 {
        let slice = data.subdata(in: offset..<(offset + 2))
        return slice.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
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
