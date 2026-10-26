import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import unittest
import subprocess
import sys
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("manager", Path(__file__).resolve().parents[1] / "scripts/manage-linux.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class ManagerTests(unittest.TestCase):
    def test_aliases_flatpak_and_wsl(self):
        apps = [dict(id="bat", name="Bat", checks=[["bat", "batcat"]]), dict(id="gui", name="GUI", gui=True, flatpak="org.test.GUI", checks=[["gui"]])]
        rows = m.scan(apps, which=lambda c: c == "batcat", flatpaks={"org.test.GUI"}, wsl=False)
        self.assertEqual([a["status"] for a in rows], ["installed", "installed"])
        self.assertEqual(m.scan(apps, which=lambda c: False, flatpaks=set(), wsl=True)[1]["status"], "unavailable")
        self.assertEqual(m.scan(apps, which=lambda c: False, flatpaks=None, wsl=False)[1]["status"], "missing")  # no Flatpak executable: known absent

    def test_dependencies_deduplicate_and_preserve_installed(self):
        rows = [dict(id="app", name="App", status="missing", dependsOn=["runtime"]), dict(id="runtime", name="Runtime", status="missing"), dict(id="existing", name="Existing", status="installed")]
        self.assertEqual([a["id"] for a in m.installation_plan(rows, ["app", "app", "existing"])], ["runtime", "app"])
        rows[1]["status"] = "unknown"
        with self.assertRaises(ValueError): m.installation_plan(rows, ["app"])
        with self.assertRaises(ValueError): m.installation_plan(rows, ["unknown"])

    def test_cycles_rejected(self):
        with self.assertRaises(ValueError):
            m.installation_plan([dict(id="a", name="A", status="missing", dependsOn=["a"])], ["a"])

    def test_catalog_recipes(self):
        apps = m.load_catalog()
        self.assertGreater(len(apps), 25)
        for distro in ("ubuntu", "fedora"):
            for app in apps:
                self.assertTrue(all(isinstance(a, str) and a for a in m.recipe(app, distro)))

    def test_public_plan_installs_nothing_and_selects_only_missing(self):
        rows = [dict(id="git", name="Git", profile="cli", status="installed"), dict(id="bun", name="Bun", profile="dev", status="missing")]
        with patch.object(m, "scan", return_value=rows), patch.object(m, "detect_distro", return_value="ubuntu"), patch.object(m.subprocess, "call") as install, patch("sys.argv", ["manage.sh", "--plan"]), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(), 0)
            install.assert_not_called()
            self.assertIn("Bun", output.getvalue())
            self.assertNotIn("Git (git)", output.getvalue())

    def test_installed_filter_is_read_only(self):
        rows = [dict(id="git", name="Git", profile="cli", status="installed"), dict(id="bun", name="Bun", profile="dev", status="missing")]
        with patch.object(m, "scan", return_value=rows), patch.object(m, "detect_distro", return_value="ubuntu"), patch.object(m.subprocess, "call") as install, patch("sys.argv", ["manage.sh", "--installed"]), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(), 0)
            install.assert_not_called()
            self.assertIn("Git", output.getvalue())
            self.assertNotIn("Bun", output.getvalue())

    def test_explicit_missing_ids_dispatch_without_profile_reexecution(self):
        rows = [dict(id="git", name="Git", profile="cli", status="installed"), dict(id="bun", name="Bun", profile="dev", status="missing")]
        after = [dict(a, status="installed") for a in rows]
        with patch.object(m, "scan", side_effect=[rows, after]), patch.object(m, "detect_distro", return_value="ubuntu"), patch.object(m.subprocess, "call", return_value=0) as install, patch("sys.argv", ["manage.sh", "--apps", "git,bun", "--yes"]), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(), 0)
            self.assertEqual(install.call_args.args[0][-2:], ["ubuntu", "bun"])

    def test_false_installer_success_is_not_accepted(self):
        rows = [dict(id="bun", name="Bun", profile="dev", status="missing")]
        with patch.object(m, "scan", return_value=rows), patch.object(m, "detect_distro", return_value="ubuntu"), patch.object(m.subprocess, "call", return_value=0), patch("sys.argv", ["manage.sh", "--apps", "bun", "--yes"]), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(), 1)

    @unittest.skipUnless(sys.platform.startswith("linux"), "real Bash sandbox")
    def test_real_runner_keeps_arguments_and_blocks_failed_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for subdir in ("scripts", "catalog", "install-common", "install-ubuntu", "bin"):
                (root / subdir).mkdir()
            for name in ("manage-linux-install.sh", "manage-linux.py"):
                (root / "scripts" / name).write_bytes((m.ROOT / "scripts" / name).read_bytes())
            catalog = [dict(id="base", name="Base", checks=[["base"]], action=["demo", "fail"]), dict(id="dependent", name="Dependent", checks=[["dependent"]], dependsOn=["base"], action=["demo", "should not run"]), dict(id="independent", name="Independent", checks=[["independent"]], action=["demo", "argument with spaces"])]
            (root / "catalog/linux-apps.json").write_text(json.dumps(catalog))
            (root / "install-common/lib.sh").write_text('cleanup() { :; }\napt_update() { :; }\napt_install() { :; }\ndemo() { printf "%s\\n" "$1" >> "$TRACE"; [[ "$1" != fail ]]; }\nrun_app() { local label="$1"; shift; "$@" || printf "%s (exit 1)\\n" "$label" >> "$GUEPARDO_FAILURES_FILE"; }\n')
            (root / "install-ubuntu/lib.sh").write_text("")
            for name, body in (("sudo", "exit 0"), ("id", "echo 1000")):
                executable = root / "bin" / name
                executable.write_text("#!/bin/sh\n" + body + "\n")
                executable.chmod(0o755)
            trace = root / "trace"
            env = dict(os.environ, HOME=str(root), XDG_STATE_HOME=str(root / "state"), TRACE=str(trace), PATH=str(root / "bin") + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["bash", str(root / "scripts/manage-linux-install.sh"), "ubuntu", "base", "dependent", "independent"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertEqual(trace.read_text().splitlines(), ["fail", "argument with spaces"])
            self.assertIn("dependent", result.stdout)


if __name__ == "__main__":
    unittest.main()
