"""Negative artifact tests: all compiler assets must be bound to the locked build."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


MANIFEST_TOOL = sys.argv.pop(1)


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.artifact = self.root / "artifact"
        self.engine = self.artifact / "out/host_release/libflutter_engine.so"
        self.engine.parent.mkdir(parents=True)
        self.engine.write_bytes(b"verified engine")
        self.compiler = self.engine.with_name("gen_snapshot")
        self.compiler.write_bytes(b"verified compiler")
        self.compiler.chmod(0o755)
        self.source_lock = self.root / "source-lock.json"
        self.source_lock.write_text(json.dumps({"flutter": {"revision": "locked"}}))
        self.nix_lock = self.root / "nix-lock.json"
        self.nix_lock.write_text(json.dumps({"source_lock_sha256": "fixture"}))
        self.configuration = self.root / "args.gn"
        self.configuration.write_text('flutter_runtime_mode = "release"\n')
        result = self.invoke("create", "--configuration", str(self.configuration),
                             "--minimum-glibc", "2.42", "--minimum-compiler-runtime",
                             "15.2", "--nixpkgs-version", "pinned")
        self.assertEqual(result.returncode, 0, result.stderr)

    def invoke(self, operation="verify", *extra):
        return subprocess.run([
            sys.executable, MANIFEST_TOOL, operation, str(self.artifact),
            "--source-lock", str(self.source_lock), "--nix-lock", str(self.nix_lock),
            "--platform", "x86_64-linux", *extra,
        ], capture_output=True, text=True)

    def rejected(self):
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("denial engine verification failed", result.stderr)

    def test_complete_artifact_passes(self):
        self.assertEqual(self.invoke().returncode, 0)

    def test_changed_engine_rejected(self):
        self.engine.write_bytes(b"changed engine")
        self.rejected()

    def test_changed_compiler_rejected(self):
        self.compiler.write_bytes(b"changed compiler")
        self.rejected()

    def test_missing_compiler_rejected(self):
        self.compiler.unlink()
        self.rejected()

    def test_extra_file_rejected(self):
        self.engine.with_name("unexpected.so").write_bytes(b"extra")
        self.rejected()

    def test_changed_executable_mode_rejected(self):
        self.compiler.chmod(0o644)
        self.rejected()

    def test_symlink_escape_rejected(self):
        self.compiler.unlink()
        self.compiler.symlink_to(self.configuration)
        self.rejected()

    def test_changed_source_lock_rejected(self):
        self.source_lock.write_text('{"flutter":{"revision":"other"}}')
        self.rejected()

    def test_changed_fetch_lock_rejected(self):
        self.nix_lock.write_text('{"source_lock_sha256":"other"}')
        self.rejected()

    def test_wrong_platform_rejected(self):
        result = self.invoke("verify", "--platform", "aarch64-linux")
        self.assertNotEqual(result.returncode, 0)

    def test_missing_configuration_record_rejected(self):
        path = self.artifact / "manifest.json"
        data = json.loads(path.read_text())
        del data["configuration_sha256"]
        path.write_text(json.dumps(data))
        self.rejected()

    def test_wrong_producer_baseline_rejected(self):
        result = self.invoke("verify", "--minimum-glibc", "2.44")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
