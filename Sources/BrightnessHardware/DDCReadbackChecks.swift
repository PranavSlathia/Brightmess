#if DEBUG
import CPrivateDisplay
import Foundation

public enum DDCReadbackChecks {
    public static func run() throws {
        struct Failure: Error { let message: String }
        var packet = [UInt8](repeating: 0, count: 4)
        guard BRDDCMakeGetVCPRequest(0x10, &packet, 4) == 0,
              packet == [0x82, 0x01, 0x10, 0xAC] else {
            throw Failure(message: "Samsung GET brightness checksum is \(packet.map { String(format: "%02X", $0) }.joined()); expected 820110AC")
        }
        guard BRDDCMakeGetVCPRequest(0x60, &packet, 4) == 0,
              packet == [0x82, 0x01, 0x60, 0xDC],
              BRDDCMakeGetVCPRequest(0x10, &packet, 3) != 0,
              BRDDCMakeGetVCPRequest(0x10, nil, 4) != 0 else {
            throw Failure(message: "GET input-source packet or buffer validation failed")
        }
        let valid: [UInt8] = [0x6E,0x88,0x02,0,0x10,0,0,100,0,52,0xF4]
        var current: UInt16 = 0, maximum: UInt16 = 0
        guard BRDDCDecodeVCPReply(0x10,valid,11,&current,&maximum) == 0, current == 52, maximum == 100 else {
            throw Failure(message: "Valid physical Samsung reply was not decoded")
        }
        var corrupt = valid; corrupt[10] ^= 1
        let empty: [UInt8] = [0x6E,0x80,0xBE,0x6E,0x80,0xBE,0x6E,0x80,0xBE,0x6E,0x80]
        guard BRDDCDecodeVCPReply(0x10,corrupt,11,&current,&maximum) != 0,
              BRDDCDecodeVCPReply(0x60,valid,11,&current,&maximum) != 0,
              BRDDCDecodeVCPReply(0x10,empty,11,&current,&maximum) != 0,
              BRDDCDecodeVCPReply(0x10,valid,3,&current,&maximum) != 0 else {
            throw Failure(message: "Corrupt/null/mismatched/truncated DDC reply was accepted")
        }
        print("DDC request/reply checks passed: hardware brightness, checksums, bounds, null, mismatched and corrupt replies.")
    }
}
#endif
