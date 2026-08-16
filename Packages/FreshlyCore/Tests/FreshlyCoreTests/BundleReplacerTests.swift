import Foundation
import Testing
import FreshlyModels
@testable import FreshlyInstaller

private final class ScriptedBundleFileOperations: BundleFileOperations, @unchecked Sendable {
    let backupDirectory: URL
    let failingMoves: Set<Int>
    private(set) var moves: [(source: URL, destination: URL)] = []
    private(set) var removals: [URL] = []

    init(backupDirectory: URL, failingMoves: Set<Int>) {
        self.backupDirectory = backupDirectory
        self.failingMoves = failingMoves
    }

    func replacementDirectory(for installedURL: URL) throws -> URL {
        backupDirectory
    }

    func moveItem(at source: URL, to destination: URL) throws {
        moves.append((source, destination))
        if failingMoves.contains(moves.count) {
            throw NSError(
                domain: "BundleReplacerTests",
                code: moves.count,
                userInfo: [NSLocalizedDescriptionKey: "Move \(moves.count) failed"]
            )
        }
    }

    func removeItem(at url: URL) throws {
        removals.append(url)
    }
}

@Suite("Bundle replacer", .serialized)
struct BundleReplacerTests {
    private let installed = URL(filePath: "/Applications/Fixture.app")
    private let update = URL(filePath: "/tmp/update/Fixture.app")
    private let backupDirectory = URL(filePath: "/tmp/replacement", directoryHint: .isDirectory)

    @Test("A failed install restores the previous bundle")
    func successfulRollback() throws {
        let files = ScriptedBundleFileOperations(
            backupDirectory: backupDirectory,
            failingMoves: [2]
        )

        do {
            try BundleReplacer(files: files).replaceBundle(at: installed, with: update)
            Issue.record("Expected the install move to fail")
        } catch let error as UpdateError {
            guard case .moveIntoPlaceFailed(let detail) = error.reason else {
                Issue.record("Expected moveIntoPlaceFailed, got \(error.reason)")
                return
            }
            #expect(detail == "Move 2 failed")
        }

        let backup = backupDirectory.appending(path: installed.lastPathComponent)
        #expect(files.moves.count == 3)
        #expect(files.moves[2].source == backup)
        #expect(files.moves[2].destination == installed)
        #expect(files.removals == [backupDirectory])
    }

    @Test("A failed rollback preserves the backup and reports its path")
    func failedRollback() throws {
        let files = ScriptedBundleFileOperations(
            backupDirectory: backupDirectory,
            failingMoves: [2, 3]
        )

        do {
            try BundleReplacer(files: files).replaceBundle(at: installed, with: update)
            Issue.record("Expected the install and restore moves to fail")
        } catch let error as UpdateError {
            guard case .rollbackFailed(
                let backupPath,
                let installedPath,
                let installationDetail,
                let restoreDetail
            ) = error.reason else {
                Issue.record("Expected rollbackFailed, got \(error.reason)")
                return
            }
            #expect(backupPath == backupDirectory.appending(path: installed.lastPathComponent).path)
            #expect(installedPath == installed.path)
            #expect(installationDetail == "Move 2 failed")
            #expect(restoreDetail == "Move 3 failed")
        }

        #expect(files.moves.count == 3)
        #expect(files.removals.isEmpty)
    }
}
