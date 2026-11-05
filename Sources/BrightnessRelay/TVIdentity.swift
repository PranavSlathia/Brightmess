import CryptoKit
import Security
import LocalAuthentication
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

protocol TVClientIdentity {
    var identity: SecIdentity { get }
    func secret(_ code: String, server: Data) throws -> Data
}

struct TVIdentity: TVClientIdentity {
    let identity: SecIdentity, publicData: Data
    private static let label = "BRIGHTMESS Android TV Remote v1"
    private static let tag = Data("dev.pranav.BrightnessRelay.tv-key.v1".utf8)
    typealias Lookup = (CFDictionary,UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    static func storedCertificate(lookup:Lookup = SecItemCopyMatching) throws -> SecCertificate? {
        // Certificate display labels are not stable on the macOS file Keychain.
        // Bind the lookup to our tagged key's public hash; never sign or export a
        // private key merely to locate an already-created certificate.
        let context=LAContext();context.interactionNotAllowed=true
        var ref:CFTypeRef?
        let keyQuery:[String:Any]=[kSecClass as String:kSecClassKey,kSecAttrKeyType as String:kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String:kSecAttrKeyClassPrivate,kSecAttrApplicationTag as String:tag,
            kSecReturnAttributes as String:true,kSecUseAuthenticationContext as String:context]
        let keyStatus=lookup(keyQuery as CFDictionary,&ref)
        if keyStatus==errSecItemNotFound{return nil}
        guard keyStatus==errSecSuccess,let attributes=ref as? [String:Any],
              let hash=attributes[kSecAttrApplicationLabel as String] as? Data else {
            throw TVError("Cannot read the saved TV key metadata (\(keyStatus)). Unlock the login Keychain, then reconnect.")
        }
        let query:[String:Any]=[kSecClass as String:kSecClassCertificate,kSecAttrPublicKeyHash as String:hash,
            kSecReturnRef as String:true,kSecMatchLimit as String:kSecMatchLimitAll,kSecUseAuthenticationContext as String:context]
        ref=nil;let status=lookup(query as CFDictionary,&ref)
        if status==errSecItemNotFound{return nil}
        guard status==errSecSuccess,let certificates=ref as? [SecCertificate] else{throw TVError("Cannot read saved TV certificates (\(status)).")}
        let now=Date()
        return certificates.compactMap { certificate -> (SecCertificate,Date)? in
            guard let before=certificateDate(certificate,kSecOIDX509V1ValidityNotBefore),
                  let after=certificateDate(certificate,kSecOIDX509V1ValidityNotAfter),before<=now,after>now else{return nil}
            return (certificate,after)
        }.max{$0.1<$1.1}?.0
    }
    private static func certificateDate(_ certificate:SecCertificate,_ oid:CFString)->Date? {
        guard let values=SecCertificateCopyValues(certificate,[oid] as CFArray,nil) as? [String:Any],
              let property=values[oid as String] as? [String:Any] else{return nil}
        if let value=property[kSecPropertyKeyValue as String] as? Date {return value}
        if let value=property[kSecPropertyKeyValue as String] as? NSNumber {return Date(timeIntervalSinceReferenceDate:value.doubleValue)}
        return nil
    }
    static func load(allowCreation:Bool = true) throws -> Self {
        let certQuery: [String:Any] = [kSecClass as String:kSecClassCertificate,kSecAttrLabel as String:label]
        let cert=try resolveCertificate(allowCreation:allowCreation,create:{try createCertificate(certQuery)})
        var identity: SecIdentity?
        let s = SecIdentityCreateWithCertificate(nil,cert,&identity)
        guard s == errSecSuccess, let identity, let pub = SecCertificateCopyKey(cert),
              let data = SecKeyCopyExternalRepresentation(pub,nil) as Data? else { throw TVError("Cannot access the paired Keychain identity (\(s)).") }
        var key:SecKey?
        let keyStatus=SecIdentityCopyPrivateKey(identity,&key)
        guard keyStatus==errSecSuccess,let key else{throw TVError("Cannot prepare the TV signing key (\(keyStatus)).")}
        // Network.framework otherwise asks Security to authorize this legacy key
        // on its shared connection queue, stalling unrelated HTTP/Air traffic.
        // This loader runs on a utility task: authorize the TLS algorithms here,
        // before creating any network connection. Never export private key data.
        try prepareSigningKey(key)
        return Self(identity:identity,publicData:data)
    }
    static func prepareSigningKey(_ key:SecKey) throws {
        var challenge=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,challenge.count,&challenge)==errSecSuccess else{throw TVError("Cannot create the local TV authorization challenge.")}
        for algorithm in [SecKeyAlgorithm.rsaSignatureMessagePSSSHA256,.rsaSignatureMessagePKCS1v15SHA256] {
            var error:Unmanaged<CFError>?
            guard SecKeyIsAlgorithmSupported(key,.sign,algorithm),
                  SecKeyCreateSignature(key,algorithm,Data(challenge) as CFData,&error) != nil else {
                throw TVError("macOS did not authorize the TV signing key. Complete its Keychain prompt, then reconnect. Saved pairing is unchanged.")
            }
        }
    }
    static func resolveCertificate(allowCreation:Bool,lookup:Lookup = SecItemCopyMatching,create:() throws -> SecCertificate) throws -> SecCertificate {
        if let found=try storedCertificate(lookup:lookup){return found}
        guard allowCreation else{throw TVError("The saved TV certificate is missing or expired. Choose Pair again with TV code to repair it. Saved pairing was not erased.")}
        return try create()
    }
    private static func createCertificate(_ certQuery: [String:Any]) throws -> SecCertificate {
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
        let cert=try makeCertificate(key:key)
        let result = SecItemAdd(certQuery.merging([kSecValueRef as String:cert]){$1} as CFDictionary,nil)
        guard result == errSecSuccess else { throw TVError("Cannot save TV certificate (\(result)).") }
        return cert
    }
    static func makeCertificate(key:SecKey,now:Date = Date()) throws -> SecCertificate {
        var err:Unmanaged<CFError>?
        guard let pub = SecKeyCopyPublicKey(key), let data = SecKeyCopyExternalRepresentation(pub,nil) as Data? else { throw TVError("Missing RSA public key.") }
        let der = TVDER.item
        let rsaOID = Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,1,1])
        func algorithm(_ id: UInt8) -> Data { der(0x30,der(6,rsaOID+Data([id]))+der(5,Data())) }
        let name = der(0x30,der(0x31,der(0x30,der(6,Data([0x55,4,3]))+der(0x0c,Data("BRIGHTMESS".utf8)))))
        let date = DateFormatter(); date.locale = Locale(identifier:"en_US_POSIX"); date.timeZone = TimeZone(secondsFromGMT:0); date.dateFormat = "yyMMddHHmmss'Z'"
        func time(_ interval: Double) -> Data { der(0x17,Data(date.string(from:Date(timeInterval:interval,since:now)).utf8)) }
        var serial = [UInt8](repeating:0,count:16)
        guard SecRandomCopyBytes(kSecRandomDefault,serial.count,&serial) == errSecSuccess else { throw TVError("No secure randomness.") }
        serial[0] = (serial[0] & 0x7f) | 1
        let bits = der(3,Data([0])+data)
        let body = der(0x30,der(2,Data(serial))+algorithm(11)+name+der(0x30,time(-86400)+time(315360000))+name+der(0x30,algorithm(1)+bits))
        guard let sig = SecKeyCreateSignature(key,.rsaSignatureMessagePKCS1v15SHA256,body as CFData,&err) as Data?,
              let cert = SecCertificateCreateWithData(nil,der(0x30,body+algorithm(11)+der(3,Data([0])+sig)) as CFData) else { throw TVError("Cannot create the pairing certificate.") }
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
