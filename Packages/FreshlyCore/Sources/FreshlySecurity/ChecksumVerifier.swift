import CryptoKit
import Foundation

/// Hashes download artifacts for sources that publish a checksum
/// (electron-updater's base64 SHA-512).
public enum ChecksumVerifier {
    public static func sha512Base64(of data: Data) -> String {
        Data(SHA512.hash(data: data)).base64EncodedString()
    }
}
