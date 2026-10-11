#!/usr/bin/env bash
# Seed the ARM64 prebuilt metadata directories the patch set expects.
#
# Denial's own build checks compare a staged engine against the files in
# prebuilt/flutter-engine/linux-arm64-*. On a source build there is no staged
# engine yet, so these are placeholders: the revision and checksum files are
# empty, which the patched tooling reads as "nothing to compare against", and
# the licence and build documentation are copies of the x86-64 originals,
# which are identical content.
#
# The patch set cannot carry these in the diff. They are new files whose bulk
# is three copies of a 30,000-line upstream licence, which would bury the
# 667 lines of actual change. Generating them keeps the diff reviewable.
set -euo pipefail

repo_dir="${1:?usage: seed-arm64-prebuilt.sh <denial-repo-dir>}"
repo_dir="$(cd -- "$repo_dir" && pwd)"
x64="$repo_dir/prebuilt/flutter-engine/linux-x64-release"

if [[ ! -d "$x64" ]]; then
  printf 'seed-arm64-prebuilt: no x86-64 prebuilt directory to copy from: %s\n' \
    "$x64" >&2
  exit 1
fi

for mode in debug profile release; do
  target="$repo_dir/prebuilt/flutter-engine/linux-arm64-$mode"
  install -d -m 0755 "$target"
  # Empty baselines. The patched checks skip the comparison when these are
  # zero-length rather than failing on a placeholder checksum.
  : >"$target/ENGINE_REVISION"
  : >"$target/FLUTTER_REVISION"
  : >"$target/args.gn"
  : >"$target/libflutter_engine.so.sha256"
  install -m 0644 "$x64/BUILD_INFO.md" "$target/BUILD_INFO.md"
  install -m 0644 "$x64/LICENSE.flutter" "$target/LICENSE.flutter"
  install -m 0644 "$x64/LICENSE.third_party" "$target/LICENSE.third_party"
done

printf 'seed-arm64-prebuilt: seeded arm64 metadata for debug, profile and release\n'