import Foundation

/// Read-only T-Cast discovery facts; a reply is a locator, never identity proof.
public enum TCLDiscovery {
    public static func request(clientID: String, milliseconds: Int64) -> Data {
        Data("1:\(milliseconds):BRIGHTMESS:PHONE:1:BRIGHTMESS:\(clientID):0:0\0".utf8)
    }
    public static func candidate(_ data: Data, expectedName: String, host: String) -> String? {
        guard data.count <= 16384, let message = String(data:data,encoding:.utf8) else { return nil }
        let fields = message.trimmingCharacters(in:CharacterSet(charactersIn:"\0")).components(separatedBy:":")
        guard fields.count >= 5, let version = Int(fields[0]), version > 0,
              fields[3] == "TV", expectedName.isEmpty || fields[2] == expectedName else { return nil }
        return isLocalIPv4(host) ? host : nil
    }
    public static func isLocalIPv4(_ host: String) -> Bool {
        let bytes = host.split(separator:".").compactMap { UInt8(String($0)) }
        guard bytes.count == 4, host.split(separator:".").count == 4,
              bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
              (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254) else { return false }
        return true
    }
}
