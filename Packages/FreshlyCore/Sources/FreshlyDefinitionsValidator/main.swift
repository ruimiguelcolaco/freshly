import Foundation
import FreshlyModels

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var packOutput: URL?
if let flagIndex = arguments.firstIndex(of: "--pack") {
    guard flagIndex + 1 < arguments.count else {
        fail("--pack needs an output path")
    }
    packOutput = URL(fileURLWithPath: arguments[flagIndex + 1])
    arguments.removeSubrange(flagIndex...(flagIndex + 1))
}
guard arguments.count == 1 else {
    fail("usage: validate-definitions <definitions-directory> [--pack <output.json>]")
}

let directory = URL(fileURLWithPath: arguments[0], isDirectory: true)
let problems = DefinitionsCatalog.validateDirectory(at: directory)

guard problems.isEmpty else {
    for problem in problems {
        print("error: \(problem)")
    }
    exit(1)
}

let catalog = DefinitionsCatalog.load(from: directory)
print("OK — \(catalog.definitions.count) definition(s) valid")

if let packOutput {
    let pack = DefinitionsPack(definitions: Array(catalog.definitions.values))
    do {
        try pack.encoded().write(to: packOutput, options: .atomic)
        print("packed catalog written to \(packOutput.path)")
    } catch {
        fail("could not write the packed catalog: \(error.localizedDescription)")
    }
}
