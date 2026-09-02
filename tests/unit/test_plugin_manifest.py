#!/usr/bin/env python3
"""test_plugin_manifest.py — Unit tests for Program Migrator plugins and wootc-manifest (#203, #232).

Validates:
  1. Plugin discovery order and shadowing precedence (Enterprise > User > Built-in).
  2. Manifest validation and schema version checks.
  3. Execution timeout enforcement on plugin detect scripts.
  4. Resilient handling of non-zero exits and malformed stdout from detect scripts.
  5. Discovery and catalog emission of custom / third-party plugins.
  6. Full scan output correctness and default-on semantics.
  7. wootc-manifest list-plugins CLI command.
"""

import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
MANIFEST_SCRIPT = REPO_ROOT / "payload" / "migration" / "wootc-manifest"


class PluginManifestTests(unittest.TestCase):

    def run_manifest(self, *args, env=None):
        cmd = [sys.executable, str(MANIFEST_SCRIPT)] + list(args)
        run_env = dict(os.environ)
        if env:
            run_env.update(env)
        proc = subprocess.run(
            cmd,
            env=run_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        return proc

    def test_list_plugins_discovers_builtin(self):
        """Verify wootc-manifest list-plugins enumerates built-in plugins."""
        proc = self.run_manifest("list-plugins")
        self.assertEqual(proc.returncode, 0, f"list-plugins failed: {proc.stderr}")
        data = json.loads(proc.stdout)
        self.assertIn("plugins", data)
        plugin_ids = {p["id"] for p in data["plugins"]}
        for expected in ["steam", "office", "browsers", "wifi", "wsl", "files", "look", "identity"]:
            self.assertIn(expected, plugin_ids, f"Expected builtin plugin {expected} in discovered list")

    def test_plugin_discovery_precedence(self):
        """Verify higher precedence plugin directories shadow lower precedence ones."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = pathlib.Path(tmpdir)
            high_dir = tmppath / "high_precedence"
            low_dir = tmppath / "low_precedence"
            high_dir.mkdir()
            low_dir.mkdir()

            # Create plugin with id 'custom-app' in low precedence
            low_plugin = low_dir / "custom-app"
            low_plugin.mkdir()
            (low_plugin / "plugin.json").write_text(json.dumps({
                "schemaVersion": 1,
                "id": "custom-app",
                "name": "Custom App (Low)",
                "version": "1.0.0",
                "description": "Low precedence",
                "category": "custom"
            }), encoding="utf-8")

            # Create plugin with same id 'custom-app' in high precedence
            high_plugin = high_dir / "custom-app"
            high_plugin.mkdir()
            (high_plugin / "plugin.json").write_text(json.dumps({
                "schemaVersion": 1,
                "id": "custom-app",
                "name": "Custom App (High)",
                "version": "2.0.0",
                "description": "High precedence",
                "category": "custom"
            }), encoding="utf-8")

            search_path = f"{high_dir}:{low_dir}"
            proc = self.run_manifest("list-plugins", env={"WOOTC_PLUGINS_DIR": search_path})
            self.assertEqual(proc.returncode, 0)
            data = json.loads(proc.stdout)
            custom = next((p for p in data["plugins"] if p["id"] == "custom-app"), None)
            self.assertIsNotNone(custom)
            self.assertEqual(custom["name"], "Custom App (High)")
            self.assertEqual(custom["version"], "2.0.0")

    def test_manifest_schema_validation(self):
        """Verify invalid plugin IDs or unsupported schema versions are ignored."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = pathlib.Path(tmpdir)
            plugins_dir = tmppath / "plugins.d"
            plugins_dir.mkdir()

            # Invalid ID (uppercase & special chars)
            bad_id_dir = plugins_dir / "Bad_ID!"
            bad_id_dir.mkdir()
            (bad_id_dir / "plugin.json").write_text(json.dumps({
                "schemaVersion": 1,
                "id": "Bad_ID!",
                "name": "Bad ID Plugin",
                "version": "1.0.0",
                "description": "Invalid",
                "category": "custom"
            }), encoding="utf-8")

            # Unsupported schemaVersion (version 99)
            future_dir = plugins_dir / "future-plugin"
            future_dir.mkdir()
            (future_dir / "plugin.json").write_text(json.dumps({
                "schemaVersion": 99,
                "id": "future-plugin",
                "name": "Future Plugin",
                "version": "1.0.0",
                "description": "Unsupported schema",
                "category": "custom"
            }), encoding="utf-8")

            proc = self.run_manifest("list-plugins", env={"WOOTC_PLUGINS_DIR": str(plugins_dir)})
            self.assertEqual(proc.returncode, 0)
            data = json.loads(proc.stdout)
            plugin_ids = {p["id"] for p in data["plugins"]}
            self.assertNotIn("Bad_ID!", plugin_ids)
            self.assertNotIn("future-plugin", plugin_ids)

    def test_detect_timeout_enforcement(self):
        """Verify detect script exceeding detectTimeoutSec is terminated and marked not detected."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = pathlib.Path(tmpdir)
            plugins_dir = tmppath / "plugins.d"
            plugins_dir.mkdir()

            slow_dir = plugins_dir / "slow-plugin"
            slow_dir.mkdir()
            (slow_dir / "plugin.json").write_text(json.dumps({
                "schemaVersion": 1,
                "id": "slow-plugin",
                "name": "Slow Plugin",
                "version": "1.0.0",
                "description": "Times out",
                "category": "slowcat",
                "execution": {
                    "detectTimeoutSec": 1
                }
            }), encoding="utf-8")

            bin_dir = slow_dir / "bin"
            bin_dir.mkdir()
            detect_script = bin_dir / "detect"
            detect_script.write_text("#!/usr/bin/env bash\nsleep 5\necho '{\"detected\":true}'\n", encoding="utf-8")
            detect_script.chmod(detect_script.stat().st_mode | stat.S_IXUSR)

            host_dir = tmppath / "host"
            (host_dir / "Users" / "alice").mkdir(parents=True)

            proc = self.run_manifest("scan", "alice", env={
                "WOOTC_PLUGINS_DIR": str(plugins_dir),
                "WOOTC_HOST": str(host_dir)
            })
            self.assertEqual(proc.returncode, 0)
            data = json.loads(proc.stdout)
            cats = {c["id"]: c for c in data["users"][0]["categories"]}
            self.assertIn("slowcat", cats)
            self.assertFalse(cats["slowcat"]["present"])
            self.assertFalse(cats["slowcat"]["defaultOn"])

    def test_detect_failure_and_malformed_output_handled_safely(self):
        """Verify detect script returning non-zero exit or garbage output is handled cleanly."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = pathlib.Path(tmpdir)
            plugins_dir = tmppath / "plugins.d"
            plugins_dir.mkdir()

            # Non-zero exit plugin
            fail_dir = plugins_dir / "failing-plugin"
            fail_dir.mkdir()
            (fail_dir / "plugin.json").write_text(json.dumps({
                "schemaVersion": 1,
                "id": "failing-plugin",
                "name": "Failing Plugin",
                "version": "1.0.0",
                "description": "Fails with exit 1",
                "category": "failcat"
            }), encoding="utf-8")
            (fail_dir / "bin").mkdir()
            fail_detect = fail_dir / "bin" / "detect"
            fail_detect.write_text("#!/usr/bin/env bash\nexit 1\n", encoding="utf-8")
            fail_detect.chmod(fail_detect.stat().st_mode | stat.S_IXUSR)

            # Malformed JSON plugin
            garbage_dir = plugins_dir / "garbage-plugin"
            garbage_dir.mkdir()
            (garbage_dir / "plugin.json").write_text(json.dumps({
                "schemaVersion": 1,
                "id": "garbage-plugin",
                "name": "Garbage Plugin",
                "version": "1.0.0",
                "description": "Outputs non-JSON",
                "category": "garbagecat"
            }), encoding="utf-8")
            (garbage_dir / "bin").mkdir()
            garbage_detect = garbage_dir / "bin" / "detect"
            garbage_detect.write_text("#!/usr/bin/env bash\necho 'NOT_JSON_AT_ALL'\nexit 0\n", encoding="utf-8")
            garbage_detect.chmod(garbage_detect.stat().st_mode | stat.S_IXUSR)

            host_dir = tmppath / "host"
            (host_dir / "Users" / "alice").mkdir(parents=True)

            proc = self.run_manifest("scan", "alice", env={
                "WOOTC_PLUGINS_DIR": str(plugins_dir),
                "WOOTC_HOST": str(host_dir)
            })
            self.assertEqual(proc.returncode, 0)
            data = json.loads(proc.stdout)
            cats = {c["id"]: c for c in data["users"][0]["categories"]}
            self.assertIn("failcat", cats)
            self.assertFalse(cats["failcat"]["present"])
            self.assertIn("garbagecat", cats)
            self.assertFalse(cats["garbagecat"]["present"])

    def test_custom_enterprise_plugin_detected(self):
        """Verify a custom third-party/enterprise plugin correctly scans and surfaces items."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = pathlib.Path(tmpdir)
            plugins_dir = tmppath / "plugins.d"
            plugins_dir.mkdir()

            corp_dir = plugins_dir / "corp-erp-bridge"
            corp_dir.mkdir()
            (corp_dir / "plugin.json").write_text(json.dumps({
                "$schema": "https://tuna-os.github.io/wootc/schemas/v1/plugin.schema.json",
                "schemaVersion": 1,
                "id": "corp-erp-bridge",
                "name": "Acme Corp ERP Profiles",
                "version": "1.0.0",
                "description": "Migrates internal ERP connections and certificates.",
                "category": "enterprise-erp",
                "author": "Acme IT",
                "ui": {
                    "defaultOn": True
                }
            }), encoding="utf-8")
            (corp_dir / "bin").mkdir()
            corp_detect = corp_dir / "bin" / "detect"
            corp_detect.write_text("""#!/usr/bin/env python3
import json, os, sys
user = os.environ.get("WOOTC_WIN_USER", "")
host = os.environ.get("WOOTC_HOST", "")
erp_conf = os.path.join(host, "Users", user, "AppData", "Roaming", "AcmeCorp", "erp.conf")
if os.path.exists(erp_conf):
    print(json.dumps({
        "detected": True,
        "items": [{"id": "prod-profile", "label": "Production ERP Profile", "detail": "Config & Certs", "fileCount": 1, "sizeBytes": 1024}],
        "summary": "1 ERP Profile"
    }))
else:
    print(json.dumps({"detected": False, "items": [], "summary": ""}))
sys.exit(0)
""", encoding="utf-8")
            corp_detect.chmod(corp_detect.stat().st_mode | stat.S_IXUSR)

            # Setup fixture host
            host_dir = tmppath / "host"
            erp_data_dir = host_dir / "Users" / "alice" / "AppData" / "Roaming" / "AcmeCorp"
            erp_data_dir.mkdir(parents=True)
            (erp_data_dir / "erp.conf").write_text("server=erp.acme.internal\n", encoding="utf-8")

            proc = self.run_manifest("scan", "alice", env={
                "WOOTC_PLUGINS_DIR": str(plugins_dir),
                "WOOTC_HOST": str(host_dir)
            })
            self.assertEqual(proc.returncode, 0)
            data = json.loads(proc.stdout)
            cats = {c["id"]: c for c in data["users"][0]["categories"]}
            self.assertIn("enterprise-erp", cats)
            self.assertTrue(cats["enterprise-erp"]["present"])
            self.assertTrue(cats["enterprise-erp"]["defaultOn"])
            self.assertEqual(cats["enterprise-erp"]["label"], "Acme Corp ERP Profiles")
            self.assertEqual(len(cats["enterprise-erp"]["items"]), 1)
            self.assertEqual(cats["enterprise-erp"]["items"][0]["id"], "prod-profile")

    def test_full_scan_with_builtin_plugins(self):
        """Verify wootc-manifest scan with builtin plugins correctly discovers realistic user data."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = pathlib.Path(tmpdir)
            host_dir = tmppath / "host"
            user_dir = host_dir / "Users" / "alice"

            # Personal folders
            for f in ["Documents", "Pictures", "Downloads"]:
                (user_dir / f).mkdir(parents=True)
                (user_dir / f / "test.txt").write_text("content", encoding="utf-8")

            # Firefox
            ff_dir = user_dir / "AppData" / "Roaming" / "Mozilla" / "Firefox"
            ff_dir.mkdir(parents=True)
            (ff_dir / "profiles.ini").write_text("[Install0]\nDefault=Profiles/p\n", encoding="utf-8")

            # Steam
            steam_vdf = host_dir / "Program Files (x86)" / "Steam" / "steamapps"
            steam_vdf.mkdir(parents=True)
            (steam_vdf / "libraryfolders.vdf").write_text('"libraryfolders" {}', encoding="utf-8")

            proc = self.run_manifest("scan", "alice", env={"WOOTC_HOST": str(host_dir)})
            self.assertEqual(proc.returncode, 0)
            data = json.loads(proc.stdout)
            self.assertEqual(data["host"], str(host_dir))
            cats = {c["id"]: c for c in data["users"][0]["categories"]}

            self.assertTrue(cats["files"]["present"])
            self.assertTrue(cats["files"]["defaultOn"])
            self.assertTrue(cats["browsers"]["present"])
            self.assertTrue(cats["games"]["present"])
            self.assertTrue(cats["identity"]["present"])
            self.assertFalse(cats["wsl"]["present"])


if __name__ == "__main__":
    unittest.main()
