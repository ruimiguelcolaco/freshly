import Foundation
import Testing
import FreshlyModels
@testable import FreshlyScanner

@Suite("AppScanner")
struct AppScannerTests {
    /// Builds a throwaway directory shaped like an Applications folder.
    private func makeApplicationsDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "FreshlyScannerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeApp(
        named name: String,
        in directory: URL,
        info: [String: Any],
        masReceipt: Bool = false
    ) throws -> URL {
        let bundle = directory.appending(path: "\(name).app", directoryHint: .isDirectory)
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appending(path: "Info.plist"))
        if masReceipt {
            let receiptDir = contents.appending(path: "_MASReceipt", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: receiptDir, withIntermediateDirectories: true)
            try Data("stub".utf8).write(to: receiptDir.appending(path: "receipt"))
        }
        return bundle
    }

    private func scan(_ locations: [URL]) async -> [InstalledApp] {
        var found: [InstalledApp] = []
        for await app in AppScanner(locations: locations).apps() {
            found.append(app)
        }
        return found
    }

    @Test("Reads identity, versions, and Sparkle feed from Info.plist")
    func readsPlistFields() async throws {
        let root = try makeApplicationsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try writeApp(named: "Demo", in: root, info: [
            "CFBundleIdentifier": "com.example.Demo",
            "CFBundleName": "Demo",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "456",
            "SUFeedURL": "https://example.com/appcast.xml",
        ])

        let apps = await scan([root])
        let app = try #require(apps.first)
        #expect(apps.count == 1)
        #expect(app.bundleID == "com.example.Demo")
        #expect(app.name == "Demo")
        #expect(app.version == "1.2.3")
        #expect(app.build == "456")
        #expect(app.sparkleFeedURL == URL(string: "https://example.com/appcast.xml"))
        #expect(app.installChannels == [.sparkle])
    }

    @Test("Detects Mac App Store installs by their receipt")
    func detectsMASReceipt() async throws {
        let root = try makeApplicationsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try writeApp(named: "StoreApp", in: root, info: [
            "CFBundleIdentifier": "com.example.StoreApp",
            "CFBundleShortVersionString": "2.0",
        ], masReceipt: true)

        let apps = await scan([root])
        #expect(apps.first?.installChannels == [.macAppStore])
    }

    @Test("Finds apps nested one directory level down, but not deeper")
    func findsNestedApps() async throws {
        let root = try makeApplicationsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let vendor = root.appending(path: "Vendor", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        _ = try writeApp(named: "Nested", in: vendor, info: [
            "CFBundleIdentifier": "com.example.Nested",
            "CFBundleShortVersionString": "1.0",
        ])
        let deep = vendor.appending(path: "Deeper", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        _ = try writeApp(named: "TooDeep", in: deep, info: [
            "CFBundleIdentifier": "com.example.TooDeep",
            "CFBundleShortVersionString": "1.0",
        ])

        let apps = await scan([root])
        #expect(apps.map(\.bundleID) == ["com.example.Nested"])
    }

    @Test("Skips bundles without identifier or version")
    func skipsIncompleteBundles() async throws {
        let root = try makeApplicationsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try writeApp(named: "NoID", in: root, info: [
            "CFBundleShortVersionString": "1.0"
        ])
        _ = try writeApp(named: "NoVersion", in: root, info: [
            "CFBundleIdentifier": "com.example.NoVersion"
        ])

        let apps = await scan([root])
        #expect(apps.isEmpty)
    }

    @Test("A missing scan location produces no apps and no crash")
    func missingLocation() async {
        let ghost = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let apps = await scan([ghost])
        #expect(apps.isEmpty)
    }
}
