import Foundation
import Security
import FreshlyModels

/// Code-signing, notarization, and Gatekeeper checks for installed apps and
/// downloaded updates, backed by the Security framework.
///
/// Invariant this module enforces (milestone 2): an update is only
/// installable when it is validly signed, passes Gatekeeper assessment, and
/// its team identifier matches the installed app's.
public struct SignatureVerifier: Sendable {
    public init() {}

    /// Reads signing information without deep validation.
    ///
    /// Scanning runs this for every installed app, so it must stay cheap:
    /// it reads who signed the bundle but does not hash its contents.
    /// Full validation (including Gatekeeper assessment) is reserved for
    /// the install pipeline, where it gates every install.
    public func signatureInfo(forAppAt url: URL) -> SignatureInfo {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return SignatureInfo(status: .unknown)
        }

        var informationRef: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &informationRef) == errSecSuccess,
              let information = informationRef as? [String: Any] else {
            return SignatureInfo(status: .unknown)
        }

        // An unsigned bundle yields signing information without an identifier.
        guard information[kSecCodeInfoIdentifier as String] != nil else {
            return SignatureInfo(status: .unsigned)
        }

        let codeFlags = information[kSecCodeInfoFlags as String] as? UInt32 ?? 0
        if codeFlags & SecCodeSignatureFlags.adhoc.rawValue != 0 {
            return SignatureInfo(status: .adHocSigned)
        }

        let teamID = information[kSecCodeInfoTeamIdentifier as String] as? String
        var identity: String?
        if let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leaf = certificates.first {
            identity = SecCertificateCopySubjectSummary(leaf) as String?
        }
        return SignatureInfo(status: .signed, teamID: teamID, signingIdentity: identity)
    }

    /// Full validation of a bundle about to be installed: every code file
    /// is hashed and checked against the signature, nested code included,
    /// under strict rules. Slow by design — install-time only.
    public func validateDeeply(bundleAt url: URL) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            throw UpdateError(.bundleUnreadable)
        }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        var validationError: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, nil, &validationError)
        guard status == errSecSuccess else {
            let detail: String
            if let cfError = validationError?.takeRetainedValue() {
                detail = String(CFErrorCopyDescription(cfError))
            } else {
                detail = "OSStatus \(status)"
            }
            throw UpdateError(.codeSignatureInvalid(detail: detail))
        }
    }
}
