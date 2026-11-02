import Foundation
import CryptoKit

public enum TVTrust {
    public static func fingerprint(_ key: Data) -> Data { Data(SHA256.hash(data:key)) }
    public static func accepts(_ key: Data, pairing: Bool, pinned: Data?) -> Bool {
        !key.isEmpty && (pairing || pinned == fingerprint(key))
    }
}

/// Pure protocol state: transport chunking, UI timing, and the TV's current IP are irrelevant here.
public struct TVHandshake {
    public enum Step { case hello, options, configuration, code, proof, verified, configuring, activating, starting, ready }
    public private(set) var step: Step
    public private(set) var features = 0
    private var secret = Data()
    public init(pairing: Bool) { step = pairing ? .hello : .configuring }
    public var hello: Data { TVWire.pair(10,TVWire.text(1,"BRIGHTMESS")+TVWire.text(2,"BRIGHTMESS")) }
    public mutating func prove(_ digest: Data) throws -> Data {
        guard step == .code, digest.count == 32 else { throw TVError("No active TV code.") }
        step = .proof; secret = digest; return TVWire.pair(40,TVWire.bytes(1,digest))
    }
    public mutating func receive(_ data: Data) throws -> Data? {
        let f = try TVWire.Fields(data)
        switch step {
        case .hello,.options,.configuration,.code,.proof:
            guard f.n[1] == 2, f.n[2] == 200 else { throw TVError("TV rejected the pairing request.") }
            let encoding = TVWire.bytes(1,TVWire.number(1,3)+TVWire.number(2,6))
            if step == .hello, f.b[11] != nil {
                step = .options; return TVWire.pair(20,encoding+TVWire.number(3,1))
            }
            if step == .options, f.b[20] != nil {
                step = .configuration; return TVWire.pair(30,encoding+TVWire.number(2,1))
            }
            if step == .configuration, f.b[31] != nil { step = .code; return nil }
            if step == .proof, let ack = f.b[41], try TVWire.Fields(ack).b[1] == secret {
                secret = Data(); step = .verified; return nil
            }
            throw TVError("Unexpected TV pairing response.")
        case .verified: return nil
        default:
            if let ping = f.b[8] { return TVWire.bytes(9,TVWire.number(1,try TVWire.Fields(ping).n[1] ?? 0)) }
            if f.b[3] != nil { throw TVError("The TV rejected the remote command.") }
            if let cfg = f.b[1], step == .configuring {
                features = (try TVWire.Fields(cfg).n[1] ?? 0) & (1+2+32+512)
                guard features & 2 != 0 else { throw TVError("TV does not support remote keys.") }
                step = .activating
                let info = TVWire.number(3,1)+TVWire.text(4,"1")+TVWire.text(5,"BRIGHTMESS")+TVWire.text(6,"1")
                return TVWire.bytes(1,TVWire.number(1,features)+TVWire.bytes(2,info))
            }
            if f.b[2] != nil, step == .activating { step = .starting; return TVWire.bytes(2,TVWire.number(1,features)) }
            if f.b[40] != nil, step == .starting { step = .ready }
            return nil
        }
    }
    public func command(code: Int, inputID: String? = nil) throws -> Data {
        guard step == .ready else { throw TVError("TV offline or connecting. No command sent.") }
        if let inputID {
            guard features & 512 != 0 else { throw TVError("TV does not accept input links. Open TV inputs instead.") }
            return try TVWire.link(inputID)
        }
        return TVWire.key(code)
    }
}
