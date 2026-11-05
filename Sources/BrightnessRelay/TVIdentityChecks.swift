#if DEBUG
import Foundation
import Security
import BrightnessCore

enum TVIdentityChecks {
    static func run() throws {
        func require(_ value:Bool,_ message:String)throws{if !value {throw TVError("TV identity check: "+message)}}
        let attributes:[String:Any]=[kSecAttrKeyType as String:kSecAttrKeyTypeRSA,kSecAttrKeySizeInBits as String:1024,
            kSecPrivateKeyAttrs as String:[kSecAttrIsPermanent as String:false]]
        guard let key=SecKeyCreateRandomKey(attributes as CFDictionary,nil) else{throw TVError("Ephemeral test key unavailable")}
        let certificate=try TVIdentity.makeCertificate(key:key),hash=Data(repeating:7,count:20)
        try TVIdentity.prepareSigningKey(key)
        var queries=0
        let found=try TVIdentity.storedCertificate { query,output in
            queries+=1
            let q=query as! [String:Any]
            if q[kSecClass as String] as? String == kSecClassKey as String {
                output?.pointee=[kSecAttrApplicationLabel as String:hash] as CFDictionary;return errSecSuccess
            }
            // macOS stored the certificate as BRIGHTMESS, not the requested label.
            if q[kSecAttrLabel as String] != nil {return errSecItemNotFound}
            guard q[kSecAttrPublicKeyHash as String] as? Data == hash else{return errSecParam}
            output?.pointee=[certificate] as CFArray;return errSecSuccess
        }
        try require(found != nil && queries==2,"Canonicalized certificate label caused a false miss and regeneration")
        let expired=try TVIdentity.makeCertificate(key:key,now:Date(timeIntervalSinceNow:-20*365.25*86400))
        let current=try TVIdentity.storedCertificate {query,output in
            let q=query as! [String:Any]
            if q[kSecClass as String] as? String == kSecClassKey as String {
                output?.pointee=[kSecAttrApplicationLabel as String:hash] as CFDictionary
            } else {output?.pointee=[expired,certificate] as CFArray}
            return errSecSuccess
        }
        try require(current.map{SecCertificateCopyData($0) as Data} == (SecCertificateCopyData(certificate) as Data),"Expired duplicate was selected")
        var creations=0
        do {
            _ = try TVIdentity.resolveCertificate(allowCreation:false,lookup:{_,_ in errSecItemNotFound},create:{creations+=1;return certificate})
            throw TVError("Reconnect regenerated a missing certificate")
        } catch let error as TVError {try require(error.localizedDescription.contains("missing or expired"),"Wrong missing-identity error")}
        try require(creations==0,"Background reconnect changed identity")
        _ = try TVIdentity.resolveCertificate(allowCreation:true,lookup:{_,_ in errSecItemNotFound},create:{creations+=1;return certificate})
        try require(creations==1,"Explicit pairing could not create its first identity")
        do {
            _ = try TVIdentity.resolveCertificate(allowCreation:true,lookup:{_,_ in errSecAuthFailed},create:{creations+=1;return certificate})
            throw TVError("Authorization error was ignored")
        } catch let error as TVError {try require(error.localizedDescription.contains("metadata"),"Authorization failure became a false miss")}
        try require(creations==1,"Authorization failure silently replaced credentials")
        print("TV identity checks passed: label-independent reuse, valid duplicate selection, no reconnect regeneration and no replacement on authorization failure.")
    }
}
#endif
