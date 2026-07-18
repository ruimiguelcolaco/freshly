import FreshlyModels

/// How a chosen update installs. A Homebrew release for a cask that was
/// installed through brew is upgraded through brew, so brew's own bookkeeping
/// stays consistent; everything else goes through the direct
/// download → verify → swap pipeline.
public enum InstallRouting {
    public static func usesBrewUpgrade(_ release: ReleaseInfo, installedCaskTokens: Set<String>) -> Bool {
        guard release.source == .homebrew, let token = release.caskToken else { return false }
        return installedCaskTokens.contains(token)
    }
}
