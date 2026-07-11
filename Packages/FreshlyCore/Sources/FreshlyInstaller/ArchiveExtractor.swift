import Foundation
import FreshlyModels
import FreshlySecurity

/// Extracts a downloaded artifact and locates the app bundle inside it.
/// Supports the formats Sparkle feeds actually ship: zip, disk images,
/// and tarballs. Installer packages (`.pkg`) are refused — installing them
/// needs privileges Freshly does not ask for.
struct ArchiveExtractor: Sendable {
    enum ArchiveFormat {
        case zip, dmg, tar, pkg
    }

    private static let tarSuffixes = [".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz", ".tar.xz", ".txz"]

    func extractApp(from artifact: URL, preferring bundleID: String, into workDir: URL) async throws -> URL {
        let destination = workDir.appending(path: "extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        switch Self.format(of: artifact) {
        case .zip:
            try await Subprocess.runChecked("/usr/bin/ditto", ["-x", "-k", artifact.path, destination.path])
        case .dmg:
            try await extractFromDiskImage(artifact, into: destination)
        case .tar:
            try await Subprocess.runChecked("/usr/bin/tar", ["-xf", artifact.path, "-C", destination.path])
        case .pkg:
            throw UpdateError(code: .installFailed, message: "Installer package updates are not supported yet")
        case nil:
            throw UpdateError(code: .installFailed, message: "Unsupported update format: \(artifact.lastPathComponent)")
        }

        guard let app = try locateApp(in: destination, preferring: bundleID) else {
            throw UpdateError(code: .installFailed, message: "The downloaded archive does not contain an app bundle")
        }
        return app
    }

    /// The artifact's format: by file extension when it has a meaningful
    /// one, by content otherwise — download endpoints like VS Code's
    /// `…/darwin-arm64/stable` produce files with no extension at all.
    static func format(of artifact: URL) -> ArchiveFormat? {
        let name = artifact.lastPathComponent.lowercased()
        if name.hasSuffix(".zip") { return .zip }
        if name.hasSuffix(".dmg") { return .dmg }
        if name.hasSuffix(".pkg") { return .pkg }
        if tarSuffixes.contains(where: name.hasSuffix) { return .tar }
        return sniffFormat(of: artifact)
    }

    /// Magic-byte detection for extensionless artifacts.
    static func sniffFormat(of artifact: URL) -> ArchiveFormat? {
        guard let handle = try? FileHandle(forReadingFrom: artifact) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 512), head.count >= 4 else { return nil }

        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) || head.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            return .zip
        }
        if head.starts(with: [0x1F, 0x8B]) || head.starts(with: [0x42, 0x5A, 0x68]) {
            return .tar // gzip/bzip2 stream; tar -xf autodetects the compression
        }
        if head.count >= 262, head[257..<262].elementsEqual("ustar".utf8) {
            return .tar
        }
        if head.starts(with: "xar!".utf8) {
            return .pkg
        }
        // Disk images end with a 512-byte "koly" trailer.
        if let size = try? handle.seekToEnd(), size >= 512 {
            try? handle.seek(toOffset: size - 512)
            if let trailer = try? handle.read(upToCount: 4), trailer.elementsEqual("koly".utf8) {
                return .dmg
            }
        }
        return nil
    }

    /// `.app` bundles at the top level or one level down, preferring the one
    /// whose bundle identifier matches the app being updated.
    func locateApp(in directory: URL, preferring bundleID: String) throws -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        let top = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for entry in top {
            if entry.pathExtension == "app" {
                candidates.append(entry)
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let nested = (try? fileManager.contentsOfDirectory(
                    at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                )) ?? []
                candidates.append(contentsOf: nested.filter { $0.pathExtension == "app" })
            }
        }

        if candidates.count > 1 {
            return candidates.first { bundleIdentifier(of: $0) == bundleID } ?? candidates.first
        }
        return candidates.first
    }

    private func bundleIdentifier(of bundle: URL) -> String? {
        let plistURL = bundle.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let info = plist as? [String: Any] else {
            return nil
        }
        return info["CFBundleIdentifier"] as? String
    }

    private func extractFromDiskImage(_ dmg: URL, into destination: URL) async throws {
        // hdiutil attach fails transiently when the disk-images daemon is
        // busy ("resource temporarily unavailable") — retry briefly before
        // giving up.
        var attachOutput = ""
        for attempt in 1...3 {
            do {
                attachOutput = try await Subprocess.runChecked(
                    "/usr/bin/hdiutil",
                    ["attach", "-plist", "-nobrowse", "-readonly", "-noautoopen", "-noverify", dmg.path]
                )
                break
            } catch {
                guard attempt < 3 else { throw error }
                try await Task.sleep(for: .seconds(Double(attempt)))
            }
        }
        guard let mountPoint = Self.mountPoint(fromAttachPlist: attachOutput) else {
            throw UpdateError(code: .installFailed, message: "Could not mount the downloaded disk image")
        }

        do {
            let mounted = URL(fileURLWithPath: mountPoint, isDirectory: true)
            let entries = try FileManager.default.contentsOfDirectory(
                at: mounted, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )
            guard let app = entries.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError(code: .installFailed, message: "The disk image does not contain an app bundle")
            }
            let copied = destination.appending(path: app.lastPathComponent)
            try await Subprocess.runChecked("/usr/bin/ditto", [app.path, copied.path])
            // Best effort: a stuck mount must not fail an already-copied update.
            _ = try? await Subprocess.run("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
        } catch {
            _ = try? await Subprocess.run("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
            throw error
        }
    }

    static func mountPoint(fromAttachPlist plist: String) -> String? {
        guard let data = plist.data(using: .utf8),
              let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = parsed as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]] else {
            return nil
        }
        return entities.compactMap { $0["mount-point"] as? String }.first
    }
}
