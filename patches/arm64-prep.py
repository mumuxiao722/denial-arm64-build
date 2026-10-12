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

# package-denial-apk pins the x86-64 minirootfs by both architecture and
# digest. Changing the architecture alone leaves the digest describing a
# different archive, and the download is verified with sha256sum --strict, so
# both move together. MINIROOTFS_URL is assembled from ALPINE_ARCH and needs
# no edit of its own.
ALPINE_ARCH_FROM = "readonly ALPINE_ARCH='x86_64'"
ALPINE_ARCH_TO = "readonly ALPINE_ARCH='aarch64'"
ALPINE_SHA_FROM = (
    "readonly MINIROOTFS_SHA256="
    "'41f73e3cf5fa919b8aa5ca6b30dc48f0da2720776d7423e2a7748211456fe081'"
)
ALPINE_SHA_TO = (
    "readonly MINIROOTFS_SHA256="
    "'f55a90f69052c5bd6f92cb09a8f47065970830b194c917a006fb94028e721259'"
)

# ALPINE_ARCH above says which architecture this build targets, so it is
# replaced. APKBUILD's arch= says which architectures the package claims to
# support, so aarch64 is added and x86_64 is kept, the way the other six
# package definitions already do it. Replacing it instead would drop upstream
# x86-64 support from the Alpine package alone.
ALPINE_PKG_ARCH_FROM = 'arch="x86_64"'
ALPINE_PKG_ARCH_TO = 'arch="x86_64 aarch64"'


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


def patch_alpine(repo):
    """Retarget the two files that hardcode x86-64 on the Alpine path.

    package-denial-apk picks the minirootfs to build in, and APKBUILD declares
    what the resulting package claims to support. Both say x86-64 upstream and
    both have to mention aarch64, for different reasons.
    """
    targets = (
        (
            os.path.join(repo, "tools", "package-denial-apk"),
            "ALPINE_ARCH",
            ALPINE_ARCH_FROM,
            ALPINE_ARCH_TO,
        ),
        (
            os.path.join(repo, "tools", "package-denial-apk"),
            "MINIROOTFS_SHA256",
            ALPINE_SHA_FROM,
            ALPINE_SHA_TO,
        ),
        (
            os.path.join(repo, "packaging", "alpine", "APKBUILD"),
            "arch",
            ALPINE_PKG_ARCH_FROM,
            ALPINE_PKG_ARCH_TO,
        ),
    )
    for path, name, old, new in targets:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        if new in text:
            continue
        count = text.count(old)
        if count != 1:
            sys.exit(
                f"arm64-prep: expected exactly one {name} definition in {path}, "
                f"found {count}"
            )
        with open(path, "w", encoding="utf-8") as f:
            f.write(text.replace(old, new, 1))
    print("arm64-prep: retargeted the Alpine build to aarch64")


def prep_checkout(repo):
    """Everything the ARM64 checkout needs before it is built.

    Both act on files inside the repo, so they take the repo directory and
    are always run together, right after the diff is applied.
    """
    seed_prebuilt(repo)
    patch_alpine(repo)


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