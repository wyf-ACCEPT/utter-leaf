import Foundation
#if canImport(CZlib)
import CZlib
#else
import zlib
#endif

public enum WireError: Error { case malformed, compression, provider(UInt32), oversized }
public enum DoubaoWire {
    public struct Response {
        public let final: Bool
        public let body: [String: Any]
        public let code: UInt32
    }
    public static func gzip(_ data: Data, decompress: Bool = false) throws -> Data {
        var stream = z_stream()
        let initialized = decompress ? inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            : deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initialized == Z_OK else { throw WireError.compression }
        defer { if decompress { inflateEnd(&stream) } else { deflateEnd(&stream) } }
        return try data.withUnsafeBytes { raw in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: raw.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var result = Data(); var buffer = [UInt8](repeating: 0, count: 16384)
            var status: Int32 = Z_OK
            repeat {
                status = buffer.withUnsafeMutableBytes { output in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(output.count)
                    return decompress ? inflate(&stream, Z_NO_FLUSH) : deflate(&stream, Z_FINISH)
                }
                guard status == Z_OK || status == Z_STREAM_END else { throw WireError.compression }
                result.append(contentsOf: buffer.prefix(buffer.count - Int(stream.avail_out)))
                guard result.count < 8 * 1024 * 1024 else { throw WireError.oversized }
                if status == Z_OK && stream.avail_in == 0 && stream.avail_out > 0 { throw WireError.compression }
            } while status != Z_STREAM_END
            return result
        }
    }
    public static func encode(kind: UInt8, sequence: Int32, payload: Data, final: Bool = false) throws -> Data {
        let compressed = try gzip(payload)
        var result = Data([0x11, (kind << 4) | (final ? 3 : 1), kind == 1 ? 0x11 : 0x01, 0])
        result.appendBE(UInt32(bitPattern: final ? -sequence : sequence))
        result.appendBE(UInt32(compressed.count)); result.append(compressed)
        return result
    }
    public static func decode(_ frame: Data) throws -> Response {
        let bytes = [UInt8](frame)
        guard bytes.count >= 8, bytes[0] >> 4 == 1 else { throw WireError.malformed }
        var offset = Int(bytes[0] & 15) * 4
        guard offset >= 4 else { throw WireError.malformed }
        let kind = bytes[1] >> 4, flags = bytes[1] & 15
        func read() throws -> UInt32 {
            guard offset + 4 <= bytes.count else { throw WireError.malformed }
            defer { offset += 4 }
            return bytes[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        if flags & 1 != 0 { _ = try read() }
        if flags & 4 != 0 { _ = try read() }
        let code = kind == 15 ? try read() : 0
        guard kind == 9 || kind == 15 else { throw WireError.malformed }
        let size = Int(try read())
        guard size <= 8 * 1024 * 1024, offset + size == bytes.count else { throw WireError.malformed }
        var payload = Data(bytes[offset..<offset + size])
        if bytes[2] & 15 == 1 { payload = try gzip(payload, decompress: true) }
        let body = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
        return Response(final: flags & 2 != 0, body: body, code: code)
    }
    public static func wav(_ pcm: Data) -> Data {
        var result = Data("RIFF".utf8); result.appendLE(UInt32(pcm.count + 36)); result.append(Data("WAVEfmt ".utf8))
        result.appendLE(UInt32(16)); result.appendLE(UInt16(1)); result.appendLE(UInt16(1))
        result.appendLE(UInt32(16000)); result.appendLE(UInt32(32000)); result.appendLE(UInt16(2)); result.appendLE(UInt16(16))
        result.append(Data("data".utf8)); result.appendLE(UInt32(pcm.count)); result.append(pcm)
        return result
    }
}
extension Data {
    mutating func appendBE(_ value: UInt32) { var n = value.bigEndian; Swift.withUnsafeBytes(of: &n) { append(contentsOf: $0) } }
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) { var n = value.littleEndian; Swift.withUnsafeBytes(of: &n) { append(contentsOf: $0) } }
}
