import Foundation
import FreshlyModels
@testable import FreshlyScanner

/// Builds real, ad-hoc-signed app bundles for installer integration tests.
/// The executable is a copy of `/bin/ls` — enough for `codesign` to produce
/// and validate a genuine signature.
enum FixtureApps {
    static func makeWorkDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "FreshlyFixtures-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func makeSignedApp(
        named name: String,
        in directory: URL,
        bundleID: String,
        version: String,
        build: String,
        edPublicKey: String? = nil
    ) throws -> URL {
        let bundle = directory.appending(path: "\(name).app", directoryHint: .isDirectory)
        let macOS = bundle.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/bin/ls"),
            to: macOS.appending(path: name)
        )

        var info: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleExecutable": name,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "CFBundlePackageType": "APPL",
        ]
        if let edPublicKey {
            info["SUPublicEDKey"] = edPublicKey
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundle.appending(path: "Contents/Info.plist"))

        try runProcess("/usr/bin/codesign", ["--force", "--sign", "-", bundle.path])
        return bundle
    }

    /// Zips a bundle the way release archives are shipped (bundle at the
    /// archive's top level).
    static func zip(_ bundle: URL) throws -> URL {
        let archive = bundle.deletingLastPathComponent()
            .appending(path: bundle.deletingPathExtension().lastPathComponent + ".zip")
        try runProcess("/usr/bin/ditto", ["-c", "-k", "--keepParent", bundle.path, archive.path])
        return archive
    }

    static func installedApp(for bundle: URL) throws -> InstalledApp {
        guard let app = AppScanner.inspect(appAt: bundle) else {
            throw NSError(domain: "FixtureApps", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Fixture bundle could not be inspected: \(bundle.path)"
            ])
        }
        return app
    }

    private static func runProcess(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(domain: "FixtureApps", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "\(tool) failed: \(detail)"
            ])
        }
    }
}
