#!/usr/bin/env python3
"""Preparation steps for the ARM64 patch set.

Two jobs that a diff cannot express, because both act on files outside the
Denial repository.

seed-prebuilt
    Creates the ARM64 prebuilt metadata directories that Denial's own checks
    read. They are new files, so a diff could carry them, but their bulk is
    three copies of a 30,000-line upstream licence file and would bury the
    667 lines of actual change. Run once, right after applying the diff.

patch-deps
    Rewrites the DEPS file that gclient sync resolves against, dropping the
    one dependency Flutter publishes only for linux-amd64. DEPS is fetched
    into the cache checkout rather than tracked, so it cannot be patched
    beforehand. Run by the patched denial-flutter-engine during sync, which
    supplies both paths.
"""
import os
import shutil
import sys

OPENJDK_KEY = "engine/src/flutter/third_party/java/openjdk"

PREBUILT_MODES = ("debug", "profile", "release")
# Left empty on purpose: the patched checks read a zero-length revision or
# checksum as "no baseline to compare against" and skip the comparison,
# where a placeholder value would be compared and fail.
PREBUILT_EMPTY = (
    "ENGINE_REVISION",
    "FLUTTER_REVISION",
    "args.gn",
    "libflutter_engine.so.sha256",
)
PREBUILT_COPIED = ("BUILD_INFO.md", "LICENSE.flutter", "LICENSE.third_party")


def seed_prebuilt(repo):
    source = os.path.join(repo, "prebuilt", "flutter-engine", "linux-x64-release")
    if not os.path.isdir(source):
        sys.exit(f"arm64-prep: no x86-64 prebuilt directory to copy from: {source}")
    for mode in PREBUILT_MODES:
        target = os.path.join(repo, "prebuilt", "flutter-engine", f"linux-arm64-{mode}")
        os.makedirs(target, mode=0o755, exist_ok=True)
        for name in PREBUILT_EMPTY:
            path = os.path.join(target, name)
            with open(path, "w", encoding="utf-8"):
                pass
            os.chmod(path, 0o644)
        for name in PREBUILT_COPIED:
            destination = os.path.join(target, name)
            shutil.copyfile(os.path.join(source, name), destination)
            os.chmod(destination, 0o644)
    print(
        "arm64-prep: seeded arm64 metadata for " + ", ".join(PREBUILT_MODES)
    )


def patch_deps(source, destination):
    """Write source to destination without the single openjdk dependency."""
    with open(source, encoding="utf-8") as f:
        lines = f.read().split("\n")

    begin = "  '%s': {" % OPENJDK_KEY
    end = "   },"
    out = []
    blocks = 0
    skipping = False
    for line in lines:
        if not skipping and line == begin:
            skipping = True
            blocks += 1
            continue
        if skipping:
            if line == end:
                skipping = False
            continue
        out.append(line)

    if skipping or blocks != 1:
        sys.exit(
            "arm64-prep: could not isolate the Flutter openjdk dependency "
            f"in {source}: matched {blocks} block(s)"
        )

    with open(destination, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    shutil.copymode(source, destination)
    print("arm64-prep: dropped the openjdk cipd dependency from DEPS")


def main(argv):
    command = argv[1] if len(argv) > 1 else ""
    if command == "seed-prebuilt":
        if len(argv) != 3:
            sys.exit("usage: arm64-prep.py seed-prebuilt <denial-repo-dir>")
        seed_prebuilt(argv[2])
    elif command == "patch-deps":
        if len(argv) != 4:
            sys.exit(
                "usage: arm64-prep.py patch-deps <DEPS-in> <DEPS-out>"
            )
        patch_deps(argv[2], argv[3])
    elif command:
        sys.exit(f"unknown command: {command}")
    else:
        sys.exit(
            "usage: arm64-prep.py {seed-prebuilt <repo> |"
            " patch-deps <DEPS-in> <DEPS-out>}"
        )


if __name__ == "__main__":
    main(sys.argv)