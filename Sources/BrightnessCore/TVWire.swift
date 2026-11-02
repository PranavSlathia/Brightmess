import Foundation

public struct TVError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

/// Small subset of Android Remote v2/Polo. Lengths count bytes, not Swift characters.
public enum TVWire {
    public static func varint(_ n: Int) -> Data {
        var n = UInt(n), data = Data()
        while n >= 128 { data.append(UInt8(n & 127) | 128); n >>= 7 }
        data.append(UInt8(n)); return data
    }
    public static func number(_ field: Int, _ n: Int) -> Data { varint(field << 3) + varint(n) }
    public static func bytes(_ field: Int, _ b: Data) -> Data { varint(field << 3 | 2) + frame(b) }
    public static func text(_ field: Int, _ s: String) -> Data { bytes(field, Data(s.utf8)) }
    public static func frame(_ b: Data) -> Data { varint(b.count) + b }
    static func read(_ bytes: [UInt8], _ pos: inout Int) throws -> Int? {
        var n = 0
        for shift in stride(from: 0, through: 56, by: 7) {
            guard pos < bytes.count else { return nil }
            let b = bytes[pos]; pos += 1
            n |= Int(b & 127) << shift
            if b < 128 { return n }
        }
        throw TVError("Invalid TV message length.")
    }
    public struct Fields {
        public var n = [Int:Int](), b = [Int:Data]()
        public init(_ data: Data) throws {
            let a = Array(data); var p = 0
            while p < a.count {
                guard let tag = try TVWire.read(a,&p), tag >= 8 else { throw TVError("Invalid TV message.") }
                let k = tag >> 3
                switch tag & 7 {
                case 0:
                    guard let v = try TVWire.read(a,&p) else { throw TVError("Truncated number.") }
                    n[k] = v
                case 1,2,5:
                    let length: Int?
                    switch tag & 7 { case 1: length = 8; case 5: length = 4; default: length = try TVWire.read(a,&p) }
                    guard let length, length <= a.count-p else { throw TVError("Truncated field.") }
                    b[k] = Data(a[p..<p+length]); p += length
                default: throw TVError("Unknown TV wire type.")
                }
            }
        }
    }
    public static func pair(_ field: Int,_ message: Data) -> Data { number(1,2)+number(2,200)+bytes(field,message) }
    public static func key(_ code: Int) -> Data { bytes(10,number(1,code)+number(2,3)) }
    public static func link(_ input: String) throws -> Data {
        // Accept only an Android TvInputInfo id, never an arbitrary URL or shell snippet.
        let pattern = #"^[A-Za-z0-9_.]+/[.A-Za-z0-9_$]+/HW[0-9]+$"#
        guard input.utf8.count <= 240, input.range(of:pattern,options:.regularExpression) != nil,
              !input.contains(where: { $0.isWhitespace }) else { throw TVError("Enter the TCL input ID from dumpsys tv_input.") }
        return bytes(90,text(1,"content://android.media.tv/passthrough/"+input.replacingOccurrences(of:"/",with:"%2F")))
    }
}

public struct TVFrames {
    private var pending = [UInt8]()
    public init() {}
    public mutating func push(_ data: Data) throws -> [Data] {
        pending.append(contentsOf:data)
        var offset = 0, messages = [Data]()
        while offset < pending.count {
            var pos = offset
            guard let size = try TVWire.read(pending,&pos) else { break }
            guard (1...65536).contains(size) else { throw TVError("Oversized or empty TV message.") }
            guard size <= pending.count-pos else { break }
            messages.append(Data(pending[pos..<pos+size])); offset = pos+size
        }
        pending.removeFirst(offset); return messages
    }
}
