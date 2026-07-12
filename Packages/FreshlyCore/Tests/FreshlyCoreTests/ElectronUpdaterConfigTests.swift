import Foundation
import Testing
import FreshlyModels

@Suite("ElectronUpdaterConfig")
struct ElectronUpdaterConfigTests {
    @Test("Generic provider resolves the channel manifest next to the base URL")
    func generic() {
        let yaml = """
        provider: generic
        url: 'https://calendar-desktop-release.notion-static.com'
        channel: latest
        updaterCacheDirName: cron-updater
        """
        #expect(ElectronUpdaterConfig.manifestURL(fromConfig: yaml)?.absoluteString
            == "https://calendar-desktop-release.notion-static.com/latest-mac.yml")
    }

    @Test("A non-default channel names its own manifest")
    func channelVariant() {
        let yaml = """
        provider: generic
        url: 'https://desktop-release.notion-static.com'
        channel: arm64
        """
        #expect(ElectronUpdaterConfig.manifestURL(fromConfig: yaml)?.absoluteString
            == "https://desktop-release.notion-static.com/arm64-mac.yml")
    }

    @Test("Trailing slashes on the base URL do not double up")
    func trailingSlash() {
        let yaml = """
        provider: generic
        url: https://example.com/manifest/
        """
        #expect(ElectronUpdaterConfig.manifestURL(fromConfig: yaml)?.absoluteString
            == "https://example.com/manifest/latest-mac.yml")
    }

    @Test("GitHub provider resolves to the latest release's manifest asset")
    func github() {
        let yaml = """
        provider: github
        owner: example-org
        repo: example-app
        """
        #expect(ElectronUpdaterConfig.manifestURL(fromConfig: yaml)?.absoluteString
            == "https://github.com/example-org/example-app/releases/latest/download/latest-mac.yml")
    }

    @Test("S3 buckets resolve via the regional endpoint, or a custom one")
    func s3() {
        // Dotted bucket (Spline): path-style, because the virtual-hosted
        // form fails TLS — verified against the live bucket.
        let dotted = """
        provider: s3
        bucket: updater.spline.design
        region: us-east-1
        acl: null
        """
        #expect(ElectronUpdaterConfig.manifestURL(fromConfig: dotted)?.absoluteString
            == "https://s3.us-east-1.amazonaws.com/updater.spline.design/latest-mac.yml")

        let plain = """
        provider: s3
        bucket: example-updates
        region: eu-west-1
        """
        #expect(ElectronUpdaterConfig.manifestURL(fromConfig: plain)?.absoluteString
            == "https://example-updates.s3.eu-west-1.amazonaws.com/latest-mac.yml")

        let r2 = """
        provider: s3
        bucket: lmstudio-updaters
        endpoint: https://174ee2ac3cc9a25a8bde971ff408f952.r2.cloudflarestorage.com
        acl: null
        """
        #expect(ElectronUpdaterConfig.manifestURL(fromConfig: r2)?.absoluteString
            == "https://174ee2ac3cc9a25a8bde971ff408f952.r2.cloudflarestorage.com/lmstudio-updaters/latest-mac.yml")
    }

    @Test("Empty URLs, unknown providers, and junk resolve to nothing")
    func unusable() {
        #expect(ElectronUpdaterConfig.manifestURL(fromConfig: """
        provider: generic
        url: ''
        """) == nil)
        #expect(ElectronUpdaterConfig.manifestURL(fromConfig: """
        provider: keygen
        url: https://example.com
        """) == nil)
        #expect(ElectronUpdaterConfig.manifestURL(fromConfig: "not yaml at all") == nil)
        #expect(ElectronUpdaterConfig.manifestURL(fromConfig: """
        provider: generic
        url: 'ftp://example.com'
        """) == nil)
    }
}
