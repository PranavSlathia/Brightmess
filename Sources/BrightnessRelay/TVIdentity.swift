import CryptoKit
import Security
import Foundation
import BrightnessCore

// RSA pairing uses the unsigned modulus and exponent, not the DER wrapper.
enum TVDER {
    static func item(_ tag: UInt8,_ b: Data) -> Data {
        var length = [UInt8](), n = b.count
        repeat { length.insert(UInt8(n & 255),at:0); n >>= 8 } while n > 0
        return Data([tag] + (b.count < 128 ? length : [0x80 | UInt8(length.count)] + length)) + b
    }
    static func rsaComponents(_ data: Data) throws -> Data {
        var a = Array(data), p = 0
        func read(_ tag: UInt8) throws -> Data {
            guard p+2 <= a.count, a[p] == tag else { throw TVError("Invalid RSA public key.") }
            var length = Int(a[p+1]); p += 2
            if length >= 128 {
                let count = length-128
                guard (1...3).contains(count), count <= a.count-p else { throw TVError("Invalid RSA length.") }
                length = 0
                for _ in 0..<count { length = length*256 + Int(a[p]); p += 1 }
            }
            guard length <= a.count-p else { throw TVError("Truncated RSA key.") }
            defer { p += length }; return Data(a[p..<p+length])
        }
        let sequence = try read(0x30)
        guard p == a.count else { throw TVError("Invalid RSA sequence.") }
        a = Array(sequence); p = 0
        let modulus = try read(2), exponent = try read(2)
        guard !modulus.isEmpty, !exponent.isEmpty, p == a.count else { throw TVError("Invalid RSA components.") }
        return Data(modulus.drop(while:{ $0 == 0 })) + Data(exponent.drop(while:{ $0 == 0 }))
    }
}

struct TVIdentity {
    let identity: SecIdentity, publicData: Data
    private static let label = "BRIGHTMESS Android TV Remote v1"
    static func load() throws -> Self {
        let certQuery: [String:Any] = [kSecClass as String:kSecClassCertificate,kSecAttrLabel as String:label]
        var ref: CFTypeRef?
        let status = SecItemCopyMatching(certQuery.merging([kSecReturnRef as String:true]){$1} as CFDictionary,&ref)
        let cert: SecCertificate
        if status == errSecSuccess, let ref, CFGetTypeID(ref) == SecCertificateGetTypeID() { cert = ref as! SecCertificate }
        else if status == errSecItemNotFound { cert = try createCertificate(certQuery) }
        else { throw TVError("Cannot open TV certificate in Keychain (\(status)).") }
        var identity: SecIdentity?
        let s = SecIdentityCreateWithCertificate(nil,cert,&identity)
        guard s == errSecSuccess, let identity, let pub = SecCertificateCopyKey(cert),
              let data = SecKeyCopyExternalRepresentation(pub,nil) as Data? else { throw TVError("Cannot access the paired Keychain identity (\(s)).") }
        return Self(identity:identity,publicData:data)
    }
    private static func createCertificate(_ certQuery: [String:Any]) throws -> SecCertificate {
        let tag = Data("dev.pranav.BrightnessRelay.tv-key.v1".utf8)
        let query: [String:Any] = [kSecClass as String:kSecClassKey,kSecAttrKeyType as String:kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String:kSecAttrKeyClassPrivate,kSecAttrApplicationTag as String:tag,kSecReturnRef as String:true]
        var found: CFTypeRef?, err: Unmanaged<CFError>?
        let s = SecItemCopyMatching(query as CFDictionary,&found)
        let key: SecKey
        if s == errSecSuccess, let found { key = found as! SecKey }
        else if s == errSecItemNotFound {
            let attrs: [String:Any] = [kSecAttrKeyType as String:kSecAttrKeyTypeRSA,kSecAttrKeySizeInBits as String:2048,
                kSecPrivateKeyAttrs as String:[kSecAttrIsPermanent as String:true,kSecAttrApplicationTag as String:tag,kSecAttrLabel as String:label]]
            guard let generated = SecKeyCreateRandomKey(attrs as CFDictionary,&err) else { throw TVError("Keychain refused to create the TV identity.") }
            key = generated
        } else { throw TVError("Keychain is unavailable (\(s)).") }
        guard let pub = SecKeyCopyPublicKey(key), let data = SecKeyCopyExternalRepresentation(pub,nil) as Data? else { throw TVError("Missing RSA public key.") }
        let der = TVDER.item
        let rsaOID = Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,1,1])
        func algorithm(_ id: UInt8) -> Data { der(0x30,der(6,rsaOID+Data([id]))+der(5,Data())) }
        let name = der(0x30,der(0x31,der(0x30,der(6,Data([0x55,4,3]))+der(0x0c,Data("BRIGHTMESS".utf8)))))
        let date = DateFormatter(); date.locale = Locale(identifier:"en_US_POSIX"); date.timeZone = TimeZone(secondsFromGMT:0); date.dateFormat = "yyMMddHHmmss'Z'"
        func time(_ interval: Double) -> Data { der(0x17,Data(date.string(from:Date(timeIntervalSinceNow:interval)).utf8)) }
        var serial = [UInt8](repeating:0,count:16)
        guard SecRandomCopyBytes(kSecRandomDefault,serial.count,&serial) == errSecSuccess else { throw TVError("No secure randomness.") }
        serial[0] = (serial[0] & 0x7f) | 1
        let bits = der(3,Data([0])+data)
        let body = der(0x30,der(2,Data(serial))+algorithm(11)+name+der(0x30,time(-86400)+time(315360000))+name+der(0x30,algorithm(1)+bits))
        guard let sig = SecKeyCreateSignature(key,.rsaSignatureMessagePKCS1v15SHA256,body as CFData,&err) as Data?,
              let cert = SecCertificateCreateWithData(nil,der(0x30,body+algorithm(11)+der(3,Data([0])+sig)) as CFData) else { throw TVError("Cannot create the pairing certificate.") }
        let result = SecItemAdd(certQuery.merging([kSecValueRef as String:cert]){$1} as CFDictionary,nil)
        guard result == errSecSuccess else { throw TVError("Cannot save TV certificate (\(result)).") }
        return cert
    }
    func secret(_ code: String, server: Data) throws -> Data {
        let c = Array(code.uppercased().utf8)
        guard c.count == 6, c.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) else { throw TVError("Enter the six hex characters shown on the TV.") }
        let bytes = stride(from:0,to:6,by:2).compactMap { UInt8(String(decoding:c[$0..<$0+2],as:UTF8.self),radix:16) }
        let hash = Data(SHA256.hash(data:try TVDER.rsaComponents(publicData)+TVDER.rsaComponents(server)+Data(bytes.dropFirst())))
        guard hash.first == bytes[0] else { throw TVError("Code does not match this TV. Try again.") }
        return hash
    }
}
