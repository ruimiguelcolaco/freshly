import CryptoKit
import Foundation

/// Verifies Sparkle EdDSA (ed25519) signatures: the appcast signs the raw
/// download artifact with the developer's private key, and the installed
/// app carries the public key (`SUPublicEDKey`) in its `Info.plist`.
///
/// This is Sparkle's trust anchor: a valid signature proves the artifact
/// comes from whoever shipped the currently installed app.
public enum EdDSAVerifier {
    public static func isValidSignature(
        _ signatureBase64: String,
        publicKeyBase64: String,
        for data: Data
    ) -> Bool {
        guard
            let signature = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
            signature.count == 64,
            let keyData = Data(base64Encoded: publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
            keyData.count == 32,
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else {
            return false
        }
        return publicKey.isValidSignature(signature, for: data)
    }
}
