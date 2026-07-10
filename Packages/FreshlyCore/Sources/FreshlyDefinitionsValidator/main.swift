import Foundation
import FreshlyModels

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: validate-definitions <definitions-directory>\n".utf8))
    exit(2)
}

let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let problems = DefinitionsCatalog.validateDirectory(at: directory)

guard problems.isEmpty else {
    for problem in problems {
        print("error: \(problem)")
    }
    exit(1)
}

let catalog = DefinitionsCatalog.load(from: directory)
print("OK — \(catalog.definitions.count) definition(s) valid")
