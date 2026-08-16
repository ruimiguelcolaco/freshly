#!/usr/bin/env python3
r"""Verify every String(localized: "...") key in Freshly/ has a catalog entry.

Loads Freshly/Localizable.xcstrings and scans Freshly/**/*.swift for
String(localized: "...") calls with a literal first argument. Interpolations
in code (\(...)) and printf placeholders in the catalog (%@, %lld, etc.) are
both collapsed to a common sentinel before comparing, so keys that differ
only in interpolation syntax still match.

Exits 1 and prints the offending keys if any code key has no matching
catalog entry. Exits 0 with a summary otherwise.
"""
import json
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG_PATH = ROOT / "Freshly/Localizable.xcstrings"
SCAN_ROOT = ROOT / "Freshly"

SENTINEL = "￼"  # object replacement character; won't appear in source strings

PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?[@dlf]+")
INTERP_RE = re.compile(r"\\\([^)]*\)")
CALL_RE = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"')
NON_LITERAL_CALL_RE = re.compile(r'String\(localized:\s*(?!")')


def norm_catalog(key: str) -> str:
    return PLACEHOLDER_RE.sub(SENTINEL, key)


def norm_code(key: str) -> str:
    return INTERP_RE.sub(SENTINEL, key)


def unescape(literal: str) -> str:
    return literal.replace('\\"', '"').replace("\\\\", "\\")


def main() -> int:
    catalog = json.loads(CATALOG_PATH.read_text())
    catalog_norm = {norm_catalog(k) for k in catalog["strings"]}

    missing = []
    skipped = []
    checked = 0

    for path in sorted(SCAN_ROOT.rglob("*.swift")):
        text = path.read_text()
        rel = path.relative_to(ROOT)

        matched_spans = []
        for m in CALL_RE.finditer(text):
            matched_spans.append((m.start(), m.end()))
            checked += 1
            key = unescape(m.group(1))
            if norm_code(key) not in catalog_norm:
                missing.append((rel, key))

        for m in NON_LITERAL_CALL_RE.finditer(text):
            if any(start <= m.start() < end for start, end in matched_spans):
                continue
            skipped.append((rel, m.start()))

    if skipped:
        print(f"Skipped {len(skipped)} String(localized:) call(s) with a non-literal argument:")
        for rel, pos in skipped:
            line = text_line_number(ROOT / rel, pos)
            print(f"  {rel}:{line}")

    if missing:
        print("Localization drift -- String(localized:) keys missing from Localizable.xcstrings:")
        for rel, key in missing:
            print(f"  {rel}: {key!r}")
        return 1

    print(f"OK -- checked {checked} String(localized:) keys, all present.")
    return 0


def text_line_number(path: pathlib.Path, offset: int) -> int:
    text = path.read_text()
    return text.count("\n", 0, offset) + 1


if __name__ == "__main__":
    sys.exit(main())
