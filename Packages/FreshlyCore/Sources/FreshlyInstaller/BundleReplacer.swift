import Foundation
import FreshlyModels

protocol BundleFileOperations: Sendable {
    func replacementDirectory(for installedURL: URL) throws -> URL
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
}

struct SystemBundleFileOperations: BundleFileOperations {
    func replacementDirectory(for installedURL: URL) throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: installedURL,
            create: true
        )
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

struct BundleReplacer: Sendable {
    private let files: any BundleFileOperations

    init(files: any BundleFileOperations = SystemBundleFileOperations()) {
        self.files = files
    }

    func replaceBundle(at installedURL: URL, with newBundle: URL) throws {
        let backupDirectory: URL
        do {
            backupDirectory = try files.replacementDirectory(for: installedURL)
        } catch {
            throw mapPermissionError(error, otherwise: { .backupPreparationFailed(detail: $0) })
        }
        let backup = backupDirectory.appending(path: installedURL.lastPathComponent)

        do {
            try files.moveItem(at: installedURL, to: backup)
        } catch {
            throw mapPermissionError(error, otherwise: { .moveAsideFailed(detail: $0) })
        }

        do {
            try files.moveItem(at: newBundle, to: installedURL)
        } catch {
            let installationError = error as NSError
            do {
                try files.moveItem(at: backup, to: installedURL)
                try? files.removeItem(at: backupDirectory)
            } catch {
                let restoreError = error as NSError
                throw UpdateError(.rollbackFailed(
                    backupPath: backup.path,
                    installedPath: installedURL.path,
                    installationDetail: installationError.localizedDescription,
                    restoreDetail: restoreError.localizedDescription
                ))
            }
            throw mapPermissionError(installationError, otherwise: { .moveIntoPlaceFailed(detail: $0) })
        }

        try? files.removeItem(at: backupDirectory)
    }

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
