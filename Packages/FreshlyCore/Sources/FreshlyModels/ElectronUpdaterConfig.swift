import Foundation

/// The update channel an electron-updater app declares in its bundled
/// `Contents/Resources/app-update.yml` — the Electron world's equivalent
/// of Sparkle's `SUFeedURL`. Freshly reduces every provider to the one
/// thing it needs: the URL of the channel manifest (`latest-mac.yml` or
/// an explicit channel variant) that lists the current release.
public enum ElectronUpdaterConfig {
    /// Resolves the manifest URL from `app-update.yml` contents.
    /// Returns `nil` for providers or shapes Freshly cannot turn into a
    /// fetchable manifest (empty URLs, unknown providers, s3 buckets
    /// without a resolvable host).
    public static func manifestURL(fromConfig yaml: String) -> URL? {
        let fields = parse(yaml)
        let channel = fields["channel"] ?? "latest"
        let manifestName = "\(channel)-mac.yml"

        switch fields["provider"] {
        case "generic":
            guard let base = fields["url"], !base.isEmpty else { return nil }
            return url(base: base, appending: manifestName)
        case "github":
            guard let owner = fields["owner"], !owner.isEmpty,
                  let repo = fields["repo"], !repo.isEmpty else { return nil }
            let host = fields["host"] ?? "github.com"
            return url(
                base: "https://\(host)/\(owner)/\(repo)/releases/latest/download",
                appending: manifestName
            )
        case "s3":
            guard let bucket = fields["bucket"], !bucket.isEmpty else { return nil }
            let base: String
            if let endpoint = fields["endpoint"], !endpoint.isEmpty {
                base = "\(endpoint)/\(bucket)"
            } else {
                let region = fields["region"] ?? "us-east-1"
                // Dotted bucket names break TLS on the virtual-hosted
                // form (the wildcard cert only covers one label), so
                // they go path-style.
                base = bucket.contains(".")
                    ? "https://s3.\(region).amazonaws.com/\(bucket)"
                    : "https://\(bucket).s3.\(region).amazonaws.com"
            }
            if let path = fields["path"], !path.isEmpty {
                return url(base: base, appending: "\(path)/\(manifestName)")
            }
            return url(base: base, appending: manifestName)
        default:
            return nil
        }
    }

    private static func url(base: String, appending name: String) -> URL? {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: "\(trimmed)/\(name)"),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }

    /// `app-update.yml` is flat `key: value` YAML. Values may be quoted;
    /// everything Freshly does not recognize is ignored.
    static func parse(_ yaml: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in yaml.split(separator: "\n") {
            guard !line.hasPrefix("#"), !line.hasPrefix(" "),
                  let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("'") && value.hasSuffix("'")) || (value.hasPrefix("\"") && value.hasSuffix("\"")) {
                value = String(value.dropFirst().dropLast())
            }
            guard !value.isEmpty, value != "null" else { continue }
            fields[key] = value
        }
        return fields
    }
}
