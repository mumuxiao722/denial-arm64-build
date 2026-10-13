# Conservative producer ABI baseline. Patch revisions do not change glibc ABI.
{
  lib,
  libcVersion,
  compilerVersion,
  isGNU,
  minimumGlibc,
  minimumCompilerRuntime,
}:
lib.versionAtLeast (lib.versions.majorMinor libcVersion) minimumGlibc
&& isGNU
&& lib.versionAtLeast (lib.versions.majorMinor compilerVersion) minimumCompilerRuntime
