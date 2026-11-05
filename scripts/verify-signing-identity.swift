// Public certificate metadata and trust only. Never exports a private key.
import Foundation
import Security
import CryptoKit

let fingerprint=CommandLine.arguments.dropFirst().first?.uppercased() ?? ""
guard fingerprint.count==40,fingerprint.allSatisfy({$0.isHexDigit}) else{fputs("Use the exact 40-character signing-certificate fingerprint.\n",stderr);exit(1)}
var raw:CFTypeRef?
let query:[String:Any]=[kSecClass as String:kSecClassCertificate,kSecMatchLimit as String:kSecMatchLimitAll,kSecReturnRef as String:true]
guard SecItemCopyMatching(query as CFDictionary,&raw)==errSecSuccess,let certificates=raw as? [SecCertificate],
      let certificate=certificates.first(where:{Insecure.SHA1.hash(data:SecCertificateCopyData($0) as Data).map{String(format:"%02X",$0)}.joined()==fingerprint}) else {
    fputs("Configured signing certificate was not found. Installed app was not changed.\n",stderr);exit(1)
}
guard let signing=SecPolicyCreateWithProperties(kSecPolicyAppleCodeSigning,nil),
      let revocation=SecPolicyCreateRevocation(CFOptionFlags(kSecRevocationOCSPMethod|kSecRevocationRequirePositiveResponse)) else{exit(1)}
var trust:SecTrust?
guard SecTrustCreateWithCertificates(certificate,[signing,revocation] as CFArray,&trust)==errSecSuccess,let trust else{exit(1)}
SecTrustSetNetworkFetchAllowed(trust,true)
var error:CFError?
guard SecTrustEvaluateWithError(trust,&error) else{
    fputs("Signing certificate failed trust/revocation verification. No ad-hoc fallback; installed app was not changed.\n",stderr)
    if let error {fputs("\(CFErrorCopyDescription(error) as String)\n",stderr)}
    exit(1)
}
print("Configured signing certificate passed code-signing trust and required revocation checks.")
