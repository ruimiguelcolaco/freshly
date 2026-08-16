#!/usr/bin/env python3
import argparse
import hashlib
import pathlib


def unreleased_notes(changelog: str) -> str:
    marker = "## [Unreleased]"
    start = changelog.index(marker) + len(marker)
    remainder = changelog[start:].lstrip("\n")
    end = remainder.find("\n## [")
    notes = remainder if end < 0 else remainder[:end]
    return notes.rstrip() + "\n"


def cask(version: str, archive: pathlib.Path) -> str:
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    return f'''cask "freshly" do
  version "{version}"
  sha256 "{digest}"

  url "https://github.com/ruimiguelcolaco/freshly/releases/download/v#{{version}}/Freshly-#{{version}}.zip"
  name "Freshly"
  desc "Native open-source macOS app updater"
  homepage "https://github.com/ruimiguelcolaco/freshly"

  app "Freshly.app"
end
'''


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Freshly release metadata")
    subparsers = parser.add_subparsers(dest="command", required=True)
    notes = subparsers.add_parser("notes")
    notes.add_argument("changelog", type=pathlib.Path)
    notes.add_argument("output", type=pathlib.Path)
    cask_parser = subparsers.add_parser("cask")
    cask_parser.add_argument("--version", required=True)
    cask_parser.add_argument("--archive", required=True, type=pathlib.Path)
    cask_parser.add_argument("--output", required=True, type=pathlib.Path)
    arguments = parser.parse_args()

    if arguments.command == "notes":
        arguments.output.write_text(
            unreleased_notes(arguments.changelog.read_text(encoding="utf-8")),
            encoding="utf-8",
        )
    else:
        arguments.output.write_text(
            cask(arguments.version, arguments.archive), encoding="utf-8"
        )


if __name__ == "__main__":
    main()
