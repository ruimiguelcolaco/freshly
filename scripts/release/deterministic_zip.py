#!/usr/bin/env python3
import argparse
import os
import pathlib
import stat
import time
import zipfile


def zip_timestamp(epoch: int) -> tuple[int, int, int, int, int, int]:
    return time.gmtime(max(epoch, 315532800))[:6]


def add_entry(archive: zipfile.ZipFile, path: pathlib.Path, root: pathlib.Path, timestamp: tuple[int, ...]) -> None:
    relative = path.relative_to(root.parent).as_posix()
    metadata = os.lstat(path)
    mode = metadata.st_mode
    if stat.S_ISDIR(mode):
        relative += "/"
        contents = b""
    elif stat.S_ISLNK(mode):
        contents = os.readlink(path).encode("utf-8")
    else:
        contents = path.read_bytes()

    entry = zipfile.ZipInfo(relative, timestamp)
    entry.create_system = 3
    entry.external_attr = mode << 16
    entry.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(entry, contents, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def create_archive(app: pathlib.Path, output: pathlib.Path, epoch: int) -> None:
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError(f"not an app bundle: {app}")
    paths = [app]
    for directory, directories, files in os.walk(app, followlinks=False):
        directories.sort()
        files.sort()
        paths.extend(pathlib.Path(directory) / name for name in directories)
        paths.extend(pathlib.Path(directory) / name for name in files)
    with zipfile.ZipFile(output, "w", allowZip64=True) as archive:
        for path in paths:
            add_entry(archive, path, app, zip_timestamp(epoch))


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a reproducible app zip")
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--epoch", type=int, required=True)
    arguments = parser.parse_args()
    create_archive(arguments.app, arguments.output, arguments.epoch)


if __name__ == "__main__":
    main()
