import Foundation
import Testing
import FreshlyModels
@testable import FreshlyInstaller

@Suite("ArchiveExtractor", .serialized)
struct ArchiveExtractorTests {
    @Test("Extracts a zip and locates the bundle inside")
    func zipExtraction() async throws {
        let workDir = try FixtureApps.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let bundle = try FixtureApps.makeSignedApp(
            named: "Zipped", in: workDir,
            bundleID: "com.freshly.Zipped", version: "1.0", build: "1"
        )
        let archive = try FixtureApps.zip(bundle)

        let extractDir = workDir.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let located = try await ArchiveExtractor().extractApp(
            from: archive, preferring: "com.freshly.Zipped", into: extractDir
        )
        #expect(located.lastPathComponent == "Zipped.app")
    }

    @Test("Extracts an app from a disk image")
    func dmgExtraction() async throws {
        let workDir = try FixtureApps.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let stage = workDir.appending(path: "dmgroot", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        _ = try FixtureApps.makeSignedApp(
            named: "Imaged", in: stage,
            bundleID: "com.freshly.Imaged", version: "1.0", build: "1"
        )
        let dmg = workDir.appending(path: "Imaged.dmg")
        try await FreshlySecurityRun("/usr/bin/hdiutil", [
            "create", "-srcfolder", stage.path, "-volname", "Imaged", "-format", "UDZO", "-quiet", dmg.path,
        ])

        let extractDir = workDir.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let located = try await ArchiveExtractor().extractApp(
            from: dmg, preferring: "com.freshly.Imaged", into: extractDir
        )
        #expect(located.lastPathComponent == "Imaged.app")
    }

    @Test("Format sniffing identifies extensionless zips and disk images")
    func sniffing() async throws {
        let workDir = try FixtureApps.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let bundle = try FixtureApps.makeSignedApp(
            named: "Sniffed", in: workDir,
            bundleID: "com.freshly.Sniffed", version: "1.0", build: "1"
        )
        let zip = try FixtureApps.zip(bundle)
        let extensionless = workDir.appending(path: "stable")
        try FileManager.default.moveItem(at: zip, to: extensionless)
        #expect(ArchiveExtractor.format(of: extensionless) == .zip)

        let extractDir = workDir.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let located = try await ArchiveExtractor().extractApp(
            from: extensionless, preferring: "com.freshly.Sniffed", into: extractDir
        )
        #expect(located.lastPathComponent == "Sniffed.app")

        let noise = workDir.appending(path: "noise")
        try Data((0..<1024).map { _ in UInt8.random(in: 0...255) }).write(to: noise)
        #expect(ArchiveExtractor.format(of: noise) == nil)
    }

    @Test("Installer packages are refused")
    func pkgRefused() async throws {
        let workDir = try FixtureApps.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let pkg = workDir.appending(path: "update.pkg")
        try Data("not really a pkg".utf8).write(to: pkg)

        await #expect(throws: UpdateError.self) {
            _ = try await ArchiveExtractor().extractApp(
                from: pkg, preferring: "com.example", into: workDir
            )
        }
    }

    @Test("Parses hdiutil's attach plist for the mount point")
    func mountPointParsing() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>system-entities</key>
            <array>
                <dict><key>content-hint</key><string>GUID_partition_scheme</string></dict>
                <dict>
                    <key>content-hint</key><string>Apple_HFS</string>
                    <key>mount-point</key><string>/Volumes/Imaged</string>
                </dict>
            </array>
        </dict></plist>
        """
        #expect(ArchiveExtractor.mountPoint(fromAttachPlist: plist) == "/Volumes/Imaged")
        #expect(ArchiveExtractor.mountPoint(fromAttachPlist: "junk") == nil)
    }
}

/// Test-local process runner (hdiutil create is test tooling, not product code).
private func FreshlySecurityRun(_ tool: String, _ arguments: [String]) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    try process.run()
    await withCheckedContinuation { continuation in
        process.terminationHandler = { _ in continuation.resume() }
    }
    guard process.terminationStatus == 0 else {
        throw UpdateError(.toolFailed(tool: tool, status: Int(process.terminationStatus), detail: ""))
    }
}
