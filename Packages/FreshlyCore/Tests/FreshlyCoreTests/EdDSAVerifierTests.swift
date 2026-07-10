import CryptoKit
import Foundation
import Testing
@testable import FreshlySecurity

@Suite("EdDSAVerifier")
struct EdDSAVerifierTests {
    @Test("A genuine signature verifies; a tampered payload does not")
    func signatureRoundTrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKeyBase64 = key.publicKey.rawRepresentation.base64EncodedString()
        let payload = Data("release artifact bytes".utf8)
        let signature = try key.signature(for: payload).base64EncodedString()

        #expect(EdDSAVerifier.isValidSignature(signature, publicKeyBase64: publicKeyBase64, for: payload))

        var tampered = payload
        tampered[0] ^= 0xFF
        #expect(!EdDSAVerifier.isValidSignature(signature, publicKeyBase64: publicKeyBase64, for: tampered))
    }

    @Test("A signature from a different key is rejected")
    func wrongKeyRejected() throws {
        let signer = Curve25519.Signing.PrivateKey()
        let otherPublicKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let payload = Data("release artifact bytes".utf8)
        let signature = try signer.signature(for: payload).base64EncodedString()

        #expect(!EdDSAVerifier.isValidSignature(signature, publicKeyBase64: otherPublicKey, for: payload))
    }

    @Test("Garbage inputs never verify (and never crash)")
    func garbageInputs() {
        let payload = Data("x".utf8)
        #expect(!EdDSAVerifier.isValidSignature("not base64!!", publicKeyBase64: "also not!!", for: payload))
        #expect(!EdDSAVerifier.isValidSignature("QUJD", publicKeyBase64: "QUJD", for: payload)) // wrong lengths
        #expect(!EdDSAVerifier.isValidSignature("", publicKeyBase64: "", for: payload))
    }
}
