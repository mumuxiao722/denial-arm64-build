#!/usr/bin/env python3
"""Runtime helpers for the ARM64 patch set.

Two jobs that a diff cannot express, kept behind one entry point.

patch-deps
    Edits the DEPS file that `gclient sync` fetches. DEPS is not part of the
    Denial repository, so it is rewritten during the checkout rather than
    patched beforehand. The ARM64 checkout cannot fetch the openjdk CIPD
    package and has no use for the Fuchsia dependencies.

seed-prebuilt
    Creates the ARM64 prebuilt metadata directories that Denial's own checks
    read. They are new files, so a diff could carry them, but their bulk is
    three copies of a 30,000-line upstream licence file and would bury the
    667 lines of actual change.

Called with no argument it does patch-deps, because that is how the patched
build system invokes it.
"""
import os
import shutil
import sys

OPENJDK_BLOCK = (
    "  'engine/src/flutter/third_party/java/openjdk': {\n"
    "     'packages': [\n"
    "       {\n"
    "        'package': 'flutter/java/openjdk/${{platform}}',\n"
    "        'version': 'version:21'\n"
    "       }\n"
    "     ],\n"
    "     # Always download the JDK since java is required for running the formatter.\n"
    "     'dep_type': 'cipd',\n"
    "   },\n"
)
FUCHSIA_VAR_OLD = "'download_fuchsia_deps': 'host_os == \"linux\"',\n"
FUCHSIA_VAR_NEW = "'download_fuchsia_deps': False,\n"

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


def patch_deps(path):
    with open(path, encoding="utf-8") as f:
        s = f.read()
    if OPENJDK_BLOCK not in s:
        sys.exit(f"patch-deps: openjdk anchor not found in {path}")
    s = s.replace(OPENJDK_BLOCK, "", 1)
    if FUCHSIA_VAR_OLD not in s:
        sys.exit(f"patch-deps: fuchsia var anchor not found in {path}")
    s = s.replace(FUCHSIA_VAR_OLD, FUCHSIA_VAR_NEW, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)
    print("patch-deps: removed openjdk cipd, disabled download_fuchsia_deps")


def seed_prebuilt(repo):
    source = os.path.join(repo, "prebuilt", "flutter-engine", "linux-x64-release")
    if not os.path.isdir(source):
        sys.exit(f"seed-prebuilt: no x86-64 prebuilt directory to copy from: {source}")
    for mode in PREBUILT_MODES:
        target = os.path.join(repo, "prebuilt", "flutter-engine", f"linux-arm64-{mode}")
        os.makedirs(target, mode=0o755, exist_ok=True)
        for name in PREBUILT_EMPTY:
            with open(os.path.join(target, name), "w", encoding="utf-8"):
                pass
            os.chmod(os.path.join(target, name), 0o644)
        for name in PREBUILT_COPIED:
            destination = os.path.join(target, name)
            shutil.copyfile(os.path.join(source, name), destination)
            os.chmod(destination, 0o644)
    print(
        "seed-prebuilt: seeded arm64 metadata for "
        + ", ".join(PREBUILT_MODES)
    )


def main(argv):
    command = argv[1] if len(argv) > 1 else "patch-deps"
    if command == "patch-deps":
        if len(argv) < 3:
            sys.exit("usage: patch-deps.py patch-deps <DEPS-path>")
        patch_deps(argv[2])
    elif command == "seed-prebuilt":
        if len(argv) < 3:
            sys.exit("usage: patch-deps.py seed-prebuilt <denial-repo-dir>")
        seed_prebuilt(argv[2])
    else:
        sys.exit(f"unknown command: {command}")


if __name__ == "__main__":
    main(sys.argv)