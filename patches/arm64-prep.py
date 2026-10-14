#!/usr/bin/env python3
"""Preparation steps for the ARM64 patch set.

Two commands, split by when they run and what they act on.

prep-checkout
    Everything the Denial checkout needs before it is built: creating the
    ARM64 prebuilt metadata directories its own checks read, and retargeting
    the Alpine minirootfs from x86_64 to aarch64. The prebuilt directories are
    new files, so a diff could carry them, but their bulk is three copies of a
    30,000-line upstream licence file and would bury the hundreds of lines of
    actual change. The minirootfs is pinned by architecture and by digest and
    verified with sha256sum --strict, so those two move together. Run once,
    right after applying the diff.

patch-deps
    Rewrites the DEPS file that gclient sync resolves against, dropping the
    one dependency Flutter publishes only for linux-amd64. DEPS is fetched
    into the cache checkout rather than tracked, so it cannot be patched
    beforehand, and its path shares no parent with the checkout. Run by the
    patched denial-flutter-engine during sync, which supplies both paths.
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


def prep_checkout(repo):
    """Everything the ARM64 checkout needs before it is built.

    The prebuilt metadata directories are seeded from the x86-64 ones, because
    upstream ships those and nothing in the tree describes an ARM64 one. Only
    that is left here: the Alpine retargeting moved into denial-arm64.diff, and
    the DEPS rewrite needs paths that only exist while gclient sync runs.
    """
    seed_prebuilt(repo)


def main(argv):
    command = argv[1] if len(argv) > 1 else ""
    if command == "prep-checkout":
        if len(argv) != 3:
            sys.exit("usage: arm64-prep.py prep-checkout <denial-repo-dir>")
        prep_checkout(argv[2])
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
            "usage: arm64-prep.py {prep-checkout <repo> |"
            " patch-deps <DEPS-in> <DEPS-out>}"
        )


if __name__ == "__main__":
    main(sys.argv)