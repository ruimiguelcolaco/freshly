#!/usr/bin/env python3
import argparse
import hashlib
import pathlib


def section_notes(changelog: str, marker: str) -> str:
    heading_start = changelog.index(marker)
    heading_end = changelog.find("\n", heading_start)
    if heading_end < 0:
        raise ValueError(f"changelog section is empty: {marker}")
    remainder = changelog[heading_end + 1 :].lstrip("\n")
    end = remainder.find("\n## [")
    notes = remainder if end < 0 else remainder[:end]
    notes = notes.rstrip()
    if not notes:
        raise ValueError(f"changelog section is empty: {marker}")
    return notes + "\n"


def release_notes(changelog: str, version: str) -> str:
    version_marker = f"## [{version}]"
    if version_marker in changelog:
        return section_notes(changelog, version_marker)
    return section_notes(changelog, "## [Unreleased]")


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


def checksums(artifacts: list[pathlib.Path]) -> str:
    lines = []
    for artifact in sorted(artifacts, key=lambda path: path.name):
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        lines.append(f"{digest}  {artifact.name}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Freshly release metadata")
    subparsers = parser.add_subparsers(dest="command", required=True)
    notes = subparsers.add_parser("notes")
    notes.add_argument("--version", required=True)
    notes.add_argument("changelog", type=pathlib.Path)
    notes.add_argument("output", type=pathlib.Path)
    cask_parser = subparsers.add_parser("cask")
    cask_parser.add_argument("--version", required=True)
    cask_parser.add_argument("--archive", required=True, type=pathlib.Path)
    cask_parser.add_argument("--output", required=True, type=pathlib.Path)
    checksum_parser = subparsers.add_parser("checksums")
    checksum_parser.add_argument("--output", required=True, type=pathlib.Path)
    checksum_parser.add_argument("artifacts", nargs="+", type=pathlib.Path)
    arguments = parser.parse_args()

    if arguments.command == "notes":
        arguments.output.write_text(
            release_notes(
                arguments.changelog.read_text(encoding="utf-8"),
                arguments.version,
            ),
            encoding="utf-8",
        )
    elif arguments.command == "cask":
        arguments.output.write_text(
            cask(arguments.version, arguments.archive), encoding="utf-8"
        )
    else:
        arguments.output.write_text(
            checksums(arguments.artifacts), encoding="utf-8"
        )


if __name__ == "__main__":
    main()
