import Foundation
import FreshlyModels
import FreshlySecurity

/// Downloads, verifies, and installs one update in place:
/// download → EdDSA → SHA-512 → extract → validate (codesign, identity,
/// downgrade, Gatekeeper) → backup → swap → relaunch.
///
/// Verification policy, in order:
/// 1. When the installed app declares an EdDSA public key, the artifact's
///    signature must verify against it. This is Sparkle's trust anchor.
/// 2. When the release publishes a SHA-512 checksum (electron-updater
///    manifests), the downloaded artifact must hash to it. Integrity only —
///    it never waives the Gatekeeper requirement below.
/// 3. The extracted bundle must pass deep code-signature validation, keep
///    the same bundle identifier, and be newer than what is installed
///    (downgrade protection).
/// 4. When the installed app has a team identifier, the update must be
///    signed by the same team.
/// 5. Without a verified EdDSA signature, Gatekeeper must accept the bundle.
///
/// Nothing touches the installed app until every check has passed, and the
/// old bundle is kept as a backup until the swap succeeds.
public struct UpdateInstaller: Sendable {
    private let session: URLSession
    private let gatekeeper: any GatekeeperAssessing
    private let verifier = SignatureVerifier()
    private let extractor = ArchiveExtractor()

    public init(
        session: URLSession = .shared,
        gatekeeper: any GatekeeperAssessing = SpctlGatekeeper()
    ) {
        self.session = session
        self.gatekeeper = gatekeeper
    }

    public func install(
        _ release: ReleaseInfo,
        over app: InstalledApp,
        quitIfRunning: Bool = false
    ) -> AsyncThrowingStream<InstallPhase, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performInstall(release, over: app, quitIfRunning: quitIfRunning) {
                        continuation.yield($0)
                    }
                    continuation.yield(.finished)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func performInstall(
        _ release: ReleaseInfo,
        over app: InstalledApp,
        quitIfRunning: Bool,
        report: @escaping @Sendable (InstallPhase) -> Void
    ) async throws {
        guard let downloadURL = release.downloadURL else {
            throw UpdateError(.noDirectDownload)
        }
        guard release.isNewer(than: app) else {
            throw UpdateError(.alreadyUpToDate(appName: app.name))
        }

        let wasRunning = try await RunningApps.quitIfNeeded(app, allowed: quitIfRunning)

        let workDir = FileManager.default.temporaryDirectory
            .appending(path: "Freshly-install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // Download.
        report(.downloading(fraction: nil))
        let artifact = try await ArtifactDownloader(session: session).download(from: downloadURL, into: workDir) {
            report(.downloading(fraction: $0))
        }

        report(.verifyingDownload)

        // Both digests hash the whole artifact. Map it once and reuse: a
        // 100–300 MB update otherwise lands in RAM in full — twice when both
        // an EdDSA signature and a SHA-512 apply. `.mappedIfSafe` keeps it out
        // of the resident set (pages fault in lazily as the hash reads them).
        var mappedArtifact: Data?
        func artifactBytes() throws -> Data {
            if let mappedArtifact { return mappedArtifact }
            let data = try Data(contentsOf: artifact, options: .mappedIfSafe)
            mappedArtifact = data
            return data
        }

        // EdDSA: the pinned key is the Sparkle feed's trust anchor, so a
        // Sparkle release for an app that pins a key MUST carry a valid
        // signature. Artifacts from other channels (a Homebrew cask URL,
        // a GitHub release) legitimately have none — they take the
        // Gatekeeper path below instead. When a signature is present it is
        // verified no matter the source.
        var edDSAVerified = false
        if let publicKey = app.sparklePublicEDKey {
            if let signature = release.edSignature {
                guard EdDSAVerifier.isValidSignature(signature, publicKeyBase64: publicKey, for: try artifactBytes()) else {
                    throw UpdateError(.signatureMismatch)
                }
                edDSAVerified = true
            } else if release.source == .sparkle {
                throw UpdateError(.feedOmittedSignature(appName: app.name))
            }
        }

        // A published SHA-512 (electron-updater manifests) must match the
        // bytes we downloaded. Integrity only — it proves the artifact is
        // the one the manifest describes, not who published it, so it
        // never waives the Gatekeeper requirement below.
        if let expected = release.sha512 {
            guard ChecksumVerifier.sha512Base64(of: try artifactBytes()) == expected else {
                throw UpdateError(.checksumMismatch)
            }
        }

        // Extract and validate the new bundle.
        report(.extracting)
        let newBundle = try await extractor.extractApp(from: artifact, preferring: app.bundleID, into: workDir)

        report(.validating)
        try validate(newBundle: newBundle, replacing: app, edDSAVerified: edDSAVerified)
        if !edDSAVerified {
            guard try await gatekeeper.assess(appAt: newBundle) else {
                throw UpdateError(.gatekeeperRejected)
            }
        }
        Quarantine.removeRecursively(at: newBundle)

        // Swap, keeping the old bundle until the new one is in place.
        report(.installing)
        try replaceBundle(at: app.path, with: newBundle)

        if wasRunning {
            report(.relaunching)
            await RunningApps.launch(appAt: app.path)
        }
    }

    private func validate(newBundle: URL, replacing app: InstalledApp, edDSAVerified: Bool) throws {
        guard let info = bundleInfo(of: newBundle) else {
            throw UpdateError(.bundleUnreadable)
        }
        guard info.bundleID == app.bundleID else {
            throw UpdateError(.differentApp(bundleID: info.bundleID))
        }
        let extracted = ReleaseInfo(version: info.version, build: info.build, source: .sparkle)
        guard !extracted.isDowngrade(over: app) else {
            throw UpdateError(.downgradeBlocked)
        }

        try verifier.validateDeeply(bundleAt: newBundle)

        if let requiredTeam = app.signature.teamID {
            let newSignature = verifier.signatureInfo(forAppAt: newBundle)
            guard newSignature.teamID == requiredTeam else {
                throw UpdateError(.teamChanged(newTeam: newSignature.teamID))
            }
        }
        _ = edDSAVerified // Gatekeeper decision happens in the caller.
    }

    private func bundleInfo(of bundle: URL) -> (bundleID: String, version: AppVersion, build: String?)? {
        let plistURL = bundle.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let info = plist as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String else {
            return nil
        }
        let short = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        guard let version = short ?? build else { return nil }
        return (bundleID, AppVersion(version), build)
    }

    private func replaceBundle(at installedURL: URL, with newBundle: URL) throws {
        let fileManager = FileManager.default
        let backupDir: URL
        do {
            backupDir = try fileManager.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: installedURL,
                create: true
            )
        } catch {
            throw mapPermissionError(error, otherwise: { .backupPreparationFailed(detail: $0) })
        }
        let backup = backupDir.appending(path: installedURL.lastPathComponent)

        do {
            try fileManager.moveItem(at: installedURL, to: backup)
        } catch {
            throw mapPermissionError(error, otherwise: { .moveAsideFailed(detail: $0) })
        }
        do {
            try fileManager.moveItem(at: newBundle, to: installedURL)
        } catch {
            // Put the old version back; never leave the user without the app.
            try? fileManager.moveItem(at: backup, to: installedURL)
            throw mapPermissionError(error, otherwise: { .moveIntoPlaceFailed(detail: $0) })
        }
        try? fileManager.removeItem(at: backupDir)
    }

    /// File operations on other apps' bundles fail with permission errors
    /// until the user grants Freshly "App Management" — surface that as an
    /// actionable error instead of a raw POSIX message.
    private func mapPermissionError(
        _ error: Error,
        otherwise reason: (String) -> UpdateError.Reason
    ) -> UpdateError {
        let nsError = error as NSError
        let permissionCodes: Set<Int> = [
            NSFileWriteNoPermissionError,
            NSFileReadNoPermissionError,
            NSFileWriteVolumeReadOnlyError,
        ]
        let isPermission = (nsError.domain == NSCocoaErrorDomain && permissionCodes.contains(nsError.code))
            || (nsError.domain == NSPOSIXErrorDomain && (nsError.code == Int(EPERM) || nsError.code == Int(EACCES)))
            || ((nsError.userInfo[NSUnderlyingErrorKey] as? NSError).map {
                $0.domain == NSPOSIXErrorDomain && ($0.code == Int(EPERM) || $0.code == Int(EACCES))
            } ?? false)
        if isPermission {
            return UpdateError(.permissionDenied)
        }
        return UpdateError(reason(nsError.localizedDescription))
    }
}
