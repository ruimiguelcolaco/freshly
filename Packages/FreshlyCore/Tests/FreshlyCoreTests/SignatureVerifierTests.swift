import Foundation
import Testing
import FreshlyModels
@testable import FreshlySecurity

@Suite("SignatureVerifier")
struct SignatureVerifierTests {
    @Test("A system app reads as signed")
    func systemAppIsSigned() {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        guard FileManager.default.fileExists(atPath: calculator.path) else {
            return // machine without the stock apps; nothing to assert
        }
        let info = SignatureVerifier().signatureInfo(forAppAt: calculator)
        #expect(info.status == .signed)
    }

    @Test("A fabricated bundle does not read as signed")
    func fakeBundleIsNotSigned() throws {
        let bundle = FileManager.default.temporaryDirectory
            .appending(path: "FreshlyFake-\(UUID().uuidString).app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: bundle.appending(path: "Contents", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: bundle) }

        let info = SignatureVerifier().signatureInfo(forAppAt: bundle)
        #expect(info.status != .signed)
        #expect(info.status != .notarized)
    }
}
