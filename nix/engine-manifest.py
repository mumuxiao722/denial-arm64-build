#!/usr/bin/env python3
"""Inventory source-built Nix engine assets and verify them before host adaptation."""

import argparse
import hashlib
import json
import re
from pathlib import Path


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def inventory(root):
    result = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"engine artifact contains a symlink: {path}")
        if path.is_file() and path != root / "manifest.json":
            result[path.relative_to(root).as_posix()] = {
                "sha256": digest(path),
                "size": path.stat().st_size,
                "executable": bool(path.stat().st_mode & 0o111),
            }
        elif not path.is_file() and not path.is_dir():
            raise ValueError(f"engine artifact contains a special file: {path}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["create", "verify"])
    parser.add_argument("root", type=Path)
    parser.add_argument("--source-lock", type=Path, required=True)
    parser.add_argument("--nix-lock", type=Path, required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--configuration", type=Path)
    parser.add_argument("--minimum-glibc")
    parser.add_argument("--minimum-compiler-runtime")
    parser.add_argument("--nixpkgs-version")
    args = parser.parse_args()
    source_lock = json.loads(args.source_lock.read_text())
    identity = {
        "schema_version": 1,
        "platform": args.platform,
        "runtime_mode": "release",
        "source_lock_sha256": digest(args.source_lock),
        "source_lock": source_lock,
        "nix_lock_sha256": digest(args.nix_lock),
    }
    manifest_path = args.root / "manifest.json"
    if args.operation == "create":
        if not all((args.configuration, args.minimum_glibc,
                    args.minimum_compiler_runtime, args.nixpkgs_version)):
            parser.error("creation requires configuration and producer baselines")
        manifest = identity | {
            "configuration_sha256": digest(args.configuration),
            "minimum_glibc": args.minimum_glibc,
            "minimum_compiler_runtime": args.minimum_compiler_runtime,
            "producer_nixpkgs_version": args.nixpkgs_version,
            "files": inventory(args.root),
        }
        manifest_path.write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    else:
        manifest = json.loads(manifest_path.read_text())
        for field, expected in identity.items():
            if manifest.get(field) != expected:
                raise ValueError(f"engine manifest {field} differs from the locked build")
        if not re.fullmatch(r"[0-9a-f]{64}", str(manifest.get("configuration_sha256", ""))):
            raise ValueError("engine manifest has no valid build configuration hash")
        for field in ("minimum_glibc", "minimum_compiler_runtime", "producer_nixpkgs_version"):
            if not isinstance(manifest.get(field), str) or not manifest[field]:
                raise ValueError(f"engine manifest has no {field}")
        for field, expected in (
                ("minimum_glibc", args.minimum_glibc),
                ("minimum_compiler_runtime", args.minimum_compiler_runtime),
                ("producer_nixpkgs_version", args.nixpkgs_version)):
            if expected is not None and manifest[field] != expected:
                raise ValueError(f"engine manifest {field} differs from the producer")
        actual = inventory(args.root)
        if manifest.get("files") != actual:
            raise ValueError("engine artifact files, checksums or executable modes differ")
        if "out/host_release/libflutter_engine.so" not in actual:
            raise ValueError("release engine is absent from the artifact")
        print("Locked engine manifest and complete artifact inventory verified")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(f"denial engine verification failed: {error}") from error
