import Foundation
import FreshlyModels
import FreshlyScanner
import FreshlySources

func fail(_ message: String, exitCode: Int32) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(exitCode)
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 1 else {
    fail("usage: suggest-definition <path-to-.app>", exitCode: 2)
}

let path = arguments[0]
guard let app = AppScanner.inspect(appAt: URL(fileURLWithPath: path)) else {
    fail("not a readable app bundle: \(path)", exitCode: 1)
}

// If the app already declares a channel the scanner can see, a catalog
// entry would be redundant — the resolver already has what it needs.
let existingSignal: String?
if app.installChannels.contains(.sparkle) {
    existingSignal = "Sparkle (SUFeedURL in Info.plist)"
} else if app.installChannels.contains(.macAppStore) {
    existingSignal = "the Mac App Store (receipt found)"
} else if app.installChannels.contains(.electron) {
    existingSignal = "electron-updater (app-update.yml found)"
} else {
    existingSignal = nil
}

if let existingSignal {
    warn("\(app.name) already updates via \(existingSignal); no definition needed.")
    exit(0)
}

// Best-effort: an unreachable or empty cask index just means no cask
// suggestion, not a failure of the tool.
let entries = (try? await HomebrewCatalog().loadEntries()) ?? []
let appFileName = app.path.lastPathComponent
let matchingTokens = HomebrewCatalog.caskTokens(matchingAppNamed: appFileName, in: entries)

var homebrewCask: String?
if matchingTokens.count == 1 {
    homebrewCask = matchingTokens[0]
} else if matchingTokens.count > 1 {
    warn("ambiguous: \(matchingTokens.count) casks claim \(appFileName) — \(matchingTokens.joined(separator: ", ")). Pick one manually, or use githubRepo/appcastURL instead.")
}

let definition = AppDefinition(
    bundleID: app.bundleID,
    name: app.name,
    homebrewCask: homebrewCask
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
do {
    let data = try encoder.encode(definition)
    print(String(decoding: data, as: UTF8.self))
} catch {
    fail("could not encode the draft definition: \(error.localizedDescription)", exitCode: 1)
}

warn("")
warn("This is a draft — fill in what the tool cannot verify on its own:")
warn("  githubRepo   owner/repo whose GitHub Releases carry this app's updates")
warn("  appcastURL   an https Sparkle feed, only if this app configures one in code")

let problems = definition.validationProblems()
if !problems.isEmpty {
    warn("")
    warn("Not yet a valid definition:")
    for problem in problems {
        warn("  - \(problem)")
    }
}

warn("")
warn("Redirect stdout to save it: suggest-definition \(path) > Definitions/\(app.bundleID).json")
