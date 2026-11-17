"""Real Windows installer tests using temporary, compiled fixture applications."""
import json
import ctypes
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


POWERSHELL = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"
COMPILER = Path(os.environ.get("SystemRoot", "C:/Windows")) / "Microsoft.NET/Framework64/v4.0.30319/csc.exe"
HELPER = Path(__file__).with_name("install-update.ps1")

STUB_SOURCE = r'''
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Web.Script.Serialization;

class TestApplication {
    static int Main() {
        string app = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        string mode = File.ReadAllText(Path.Combine(app, "_internal", "mode.txt"));
        if (mode == "old") {
            File.WriteAllText(Path.Combine(app, "old-started"), "ready");
            return 0;
        }
        if (mode == "fail") return 1;
        string transaction = Path.Combine(Path.GetDirectoryName(app), "." + Path.GetFileName(app) + ".yecatz-update");
        JavaScriptSerializer serializer = new JavaScriptSerializer();
        var config = serializer.Deserialize<Dictionary<string, object>>(File.ReadAllText(Path.Combine(transaction, "config.json")));
        var ack = new Dictionary<string, object> {
            {"token", mode == "wrong-token" ? "wrong" : config["token"]},
            {"pid", Process.GetCurrentProcess().Id},
            {"tag", config["tag"]}
        };
        File.WriteAllText(Path.Combine(transaction, "ready.tmp"), serializer.Serialize(ack));
        File.Move(Path.Combine(transaction, "ready.tmp"), Path.Combine(transaction, "ready.json"));
        Thread.Sleep(mode == "wrong-token" ? 500 : 6000);
        return 0;
    }
}
'''


@unittest.skipUnless(os.name == "nt" and POWERSHELL.exists() and COMPILER.exists(), "Requires Windows PowerShell and .NET C# compiler")
class InstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiler_directory = tempfile.TemporaryDirectory(prefix="yecatz-installer-compiler-")
        root = Path(cls.compiler_directory.name)
        source = root / "Fixture.cs"
        source.write_text(STUB_SOURCE, encoding="utf-8")
        cls.executable = root / "Yecatz.exe"
        result = subprocess.run([str(COMPILER), "/nologo", "/target:winexe", "/reference:System.Web.Extensions.dll",
                                 "/out:" + str(cls.executable), str(source)], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.compiler_directory.cleanup()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="yecatz-installer-test-")
        self.root = Path(self.directory.name) / "含空格 [fixture]"
        self.root.mkdir()
        self.target = self.root / "Yecatz"
        self.transaction = self.root / ".Yecatz.yecatz-update"
        self.target.mkdir()
        self.transaction.mkdir()
        self.incoming = self.transaction / "Yecatz"
        self.incoming.mkdir()
        for app, mode in ((self.target, "old"), (self.incoming, "success")):
            shutil.copy2(self.executable, app / "Yecatz.exe")
            (app / "_internal").mkdir()
            (app / "_internal/mode.txt").write_text(mode)
        (self.incoming / "update-version.json").write_text('{"version":"2.0.0_W"}')
        (self.target / "notes.txt").write_text("kept at its original path")
        shutil.copy2(HELPER, self.transaction / HELPER.name)
        self.config = {"target": str(self.target), "parent_pid": 2147483647,
                       "tag": "2.0.0_W", "token": "fixture-test-token"}
        (self.transaction / "config.json").write_text(json.dumps(self.config), encoding="utf-8")

    def tearDown(self):
        # Fixture processes have a bounded lifetime, then release their executable.
        for attempt in range(80):
            try:
                self.directory.cleanup()
                return
            except PermissionError:
                if attempt == 79:
                    raise
                time.sleep(0.1)

    def run_helper(self, *arguments):
        return subprocess.run([str(POWERSHELL), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                               "-File", str(self.transaction / HELPER.name), "-Transaction", str(self.transaction),
                               *arguments],
                              cwd=str(self.root), capture_output=True, timeout=45)

    def diagnostics(self, result):
        log = self.transaction / "result.txt"
        return repr(result.stdout + result.stderr) + (log.read_text(encoding="utf-8") if log.exists() else "")

    def test_success_replaces_old_installation_and_cleans_backup(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, self.diagnostics(result))
        self.assertEqual((self.target / "_internal/mode.txt").read_text(), "success")
        self.assertEqual((self.target / "notes.txt").read_text(), "kept at its original path")
        self.assertFalse(self.transaction.exists())

    def test_failed_start_restores_and_relaunches_old_application(self):
        (self.incoming / "_internal/mode.txt").write_text("fail")
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / "_internal/mode.txt").read_text(), "old", self.diagnostics(result))
        self.assertFalse((self.target / "update-version.json").exists())
        self.assertEqual((self.transaction / "failed/_internal/mode.txt").read_text(), "fail")
        for _ in range(40):
            if (self.target / "old-started").exists():
                break
            time.sleep(0.05)
        self.assertTrue((self.target / "old-started").exists(), self.diagnostics(result))

    def test_wrong_readiness_token_does_not_delete_old_version(self):
        (self.incoming / "_internal/mode.txt").write_text("wrong-token")
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / "_internal/mode.txt").read_text(), "old", self.diagnostics(result))
        self.assertFalse((self.target / "update-version.json").exists())

    def test_rejects_configuration_target_outside_transaction_sibling(self):
        self.config["target"] = str(self.root / "Unrelated")
        (self.transaction / "config.json").write_text(json.dumps(self.config), encoding="utf-8")
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / "_internal/mode.txt").read_text(), "old")
        self.assertEqual((self.incoming / "_internal/mode.txt").read_text(), "success")

    def test_initial_rename_failure_restarts_existing_application(self):
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p,
                                      ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p]
        kernel.CreateFileW.restype = ctypes.c_void_p
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        # Hold the original executable without delete sharing to block its rename.
        handle = kernel.CreateFileW(str(self.target / "Yecatz.exe"), 0x1, 0x3, None, 3, 0x80, None)
        self.assertNotEqual(handle, ctypes.c_void_p(-1).value)
        try:
            result = self.run_helper()
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((self.target / "_internal/mode.txt").read_text(), "old", self.diagnostics(result))
            self.assertEqual((self.incoming / "_internal/mode.txt").read_text(), "success")
            for _ in range(40):
                if (self.target / "old-started").exists():
                    break
                time.sleep(0.05)
            self.assertTrue((self.target / "old-started").exists(), self.diagnostics(result))
        finally:
            kernel.CloseHandle(handle)

    def test_recovery_restores_executable_missing_between_renames(self):
        backup = self.transaction / "previous"
        backup.mkdir()
        (self.transaction / "old-metadata-absent").touch()
        (self.transaction / "applying").touch()
        (self.target / "Yecatz.exe").rename(backup / "Yecatz.exe")
        self.assertFalse((self.target / "Yecatz.exe").exists())
        (self.target / "notes.txt").write_text("edited during installation")
        result = self.run_helper("-Recover")
        self.assertEqual(result.returncode, 0, self.diagnostics(result))
        self.assertTrue((self.target / "Yecatz.exe").exists())
        self.assertEqual((self.target / "notes.txt").read_text(), "edited during installation")
        self.assertTrue((self.transaction / "rolled-back").exists())

    def test_recovery_replays_rollback_after_new_runtime_was_moved_aside(self):
        backup = self.transaction / "previous"
        backup.mkdir()
        failed = self.transaction / "failed"
        failed.mkdir()
        (self.transaction / "old-metadata-absent").touch()
        (self.transaction / "applying").touch()
        (self.target / "_internal").rename(backup / "_internal")
        (self.incoming / "_internal").rename(failed / "_internal")
        (self.incoming / "update-version.json").rename(self.target / "update-version.json")
        result = self.run_helper("-Recover")
        self.assertEqual(result.returncode, 0, self.diagnostics(result))
        self.assertEqual((self.target / "_internal/mode.txt").read_text(), "old")
        self.assertFalse((self.target / "update-version.json").exists())

    def test_recovery_finishes_committed_cleanup_without_changing_runtime(self):
        (self.transaction / "applying").touch()
        (self.transaction / "committed").touch()
        (self.transaction / "previous").mkdir()
        result = self.run_helper("-Recover")
        self.assertEqual(result.returncode, 0, self.diagnostics(result))
        self.assertEqual((self.target / "_internal/mode.txt").read_text(), "old")
        self.assertEqual((self.target / "notes.txt").read_text(), "kept at its original path")
        self.assertFalse(self.transaction.exists())


@unittest.skipUnless(os.name == "nt" and os.environ.get("YECATZ_TEST_DIST"), "Set YECATZ_TEST_DIST to test a built application")
class FrozenApplicationTests(unittest.TestCase):
    def test_real_application_confirms_startup_and_cleans_old_installation(self):
        distribution = Path(os.environ["YECATZ_TEST_DIST"]).resolve()
        self.assertTrue((distribution / "Yecatz.exe").is_file())
        tag = json.loads((distribution / "update-version.json").read_text(encoding="utf-8-sig"))["version"]
        with tempfile.TemporaryDirectory(prefix="yecatz-frozen-test-") as directory:
            root = Path(directory)
            target = root / "Yecatz"
            transaction = root / ".Yecatz.yecatz-update"
            transaction.mkdir()
            shutil.copytree(distribution, target)
            shutil.copytree(distribution, transaction / "Yecatz")
            (target / "old-only-marker").write_text("old version")
            config = {"target": str(target), "parent_pid": 2147483647, "tag": tag, "token": "frozen-test-token"}
            (transaction / "config.json").write_text(json.dumps(config), encoding="utf-8")
            shutil.copy2(HELPER, transaction / HELPER.name)
            environment = os.environ.copy()
            environment["QT_QPA_PLATFORM"] = "offscreen"
            environment["APPDATA"] = str(root / "appdata")
            environment["YECATZ_FIXTURE_EXE"] = str(target / "Yecatz.exe")
            helper = subprocess.Popen(
                [str(POWERSHELL), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                 str(transaction / HELPER.name), "-Transaction", str(transaction)],
                cwd=str(root), env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            acknowledgment = None
            try:
                deadline = time.monotonic() + 80
                while helper.poll() is None and time.monotonic() < deadline:
                    ready = transaction / "ready.json"
                    if acknowledgment is None and ready.exists():
                        acknowledgment = json.loads(ready.read_text(encoding="utf-8"))
                    time.sleep(0.05)
                helper.wait(timeout=5)
                result = transaction / "result.txt"
                diagnostic = result.read_text(encoding="utf-8") if result.exists() else "No installer error log"
                self.assertEqual(helper.returncode, 0, diagnostic)
                self.assertIsNotNone(acknowledgment, "Frozen application did not acknowledge GUI initialization")
                self.assertEqual(acknowledgment["token"], "frozen-test-token")
                self.assertEqual((target / "old-only-marker").read_text(), "old version")
                self.assertFalse(transaction.exists())
            finally:
                if helper.poll() is None:
                    helper.terminate()
                    helper.wait(timeout=10)
                # Only fixture executables at this exact temporary path may be stopped.
                subprocess.run(
                    [str(POWERSHELL), "-NoProfile", "-NonInteractive", "-Command",
                     "Get-Process -Name Yecatz -ErrorAction SilentlyContinue | "
                     "Where-Object { $_.Path -eq $env:YECATZ_FIXTURE_EXE } | Stop-Process -Force"],
                    env=environment, capture_output=True, timeout=15,
                )
                time.sleep(0.5)


if __name__ == "__main__":
    unittest.main()
