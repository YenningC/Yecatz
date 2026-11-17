"""Exercise the embedded macOS transaction script using temporary fake app bundles.

Run with Python 3 and the macOS Swift toolchain. The tests use the native bundle
exchange and stub the application launch after rollback.
"""
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest

if sys.platform == "darwin":
    import fcntl


ROOT = Path(__file__).resolve().parents[1]
@unittest.skipUnless(sys.platform == "darwin", "requires the macOS bundle exchange API")
class MacUpdateHelperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(prefix="yecatz-swap-")
        cls.addClassCleanup(temp.cleanup)
        cls.swap = Path(temp.name) / "yecatz-update-swap"
        compiler = ["/usr/bin/xcrun", "swiftc"]
        if os.environ.get("SDKROOT"):
            compiler.extend(["-sdk", os.environ["SDKROOT"]])
        subprocess.run(compiler + [str(ROOT / "tools/mac_update_swap.swift"), "-o", str(cls.swap)], check=True)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="yecatz mac 更新 [test] & ")
        self.base = Path(self.temp.name)
        self.target = self.base / "Yecatz [正式版].app"
        self.stage = self.base / ".Yecatz-update-test"
        self.lock = self.base / ".update-lock"
        self.target.mkdir()
        (self.target / "old.txt").write_text("old")
        self.replacement = self.stage / "unpacked/Yecatz.app"
        self.executable = self.replacement / "Contents/MacOS/Yecatz"
        self.executable.parent.mkdir(parents=True)
        (self.replacement / "new.txt").write_text("new")
        self.staged_swap = self.stage / self.swap.name
        shutil.copy2(self.swap, self.staged_swap)
        source = (ROOT / "Updates.swift").read_text(encoding="utf-8-sig")
        helper = re.search(r'private static let helper = #"""\n(.*?)\n    """#', source, re.S)
        self.assertIsNotNone(helper)
        script = textwrap.dedent(helper.group(1)) + "\n"
        # Replace the macOS GUI launcher only, so rollback cannot open an application.
        script = script.replace('/usr/bin/open -n "$target" --args --yecatz-update-error "$stage"',
                                'printf "%s\\n" "$target" > "$stage/reopened"')
        self.script = self.base / "install.sh"
        self.script.write_text(script, encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def helper_command(self, app_script):
        self.executable.write_text("#!/bin/sh\n" + app_script, encoding="utf-8")
        self.executable.chmod(0o755)
        return ["/bin/sh", str(self.script), str(self.target), str(self.stage),
                "99999999", "test-token"]

    def run_helper(self, app_script):
        with self.lock.open("a+b") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            process = subprocess.Popen(self.helper_command(app_script), stdin=lock, stdout=subprocess.DEVNULL,
                                       stderr=subprocess.PIPE, text=True)
        _, stderr = process.communicate(timeout=20)
        return process.returncode, stderr

    def assert_lock_available(self):
        with self.lock.open("a+b") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_success_replaces_and_cleans_old_version(self):
        code, stderr = self.run_helper('printf "%s" "$$" > "$0.pid"\nprintf "%s" "$4" > "$2/ready"\nexec sleep 20\n')
        pid_file = self.target / "Contents/MacOS/Yecatz.pid"
        try:
            self.assertEqual(code, 0, stderr)
            self.assertTrue((self.target / "new.txt").exists())
            self.assertFalse((self.target / "old.txt").exists())
            self.assertFalse(self.stage.exists())
            self.assert_lock_available()
        finally:
            if pid_file.exists():
                try:
                    os.kill(int(pid_file.read_text()), signal.SIGTERM)
                except ProcessLookupError:
                    pass

    def test_launch_failure_restores_original(self):
        code, _ = self.run_helper("exit 1\n")
        self.assertNotEqual(code, 0)
        self.assertTrue((self.target / "old.txt").exists())
        self.assertTrue((self.stage / "failed.app/new.txt").exists())
        self.assertTrue((self.stage / "failure.txt").exists())
        self.assertTrue((self.stage / "reopened").exists())
        self.assert_lock_available()

    def test_crash_immediately_after_acknowledgment_restores_original(self):
        code, _ = self.run_helper('printf "%s" "$4" > "$2/ready"\nsleep 1\nexit 1\n')
        self.assertNotEqual(code, 0)
        self.assertTrue((self.target / "old.txt").exists())
        self.assert_lock_available()

    def test_missing_replacement_keeps_original(self):
        # The replacement disappears after preparation, before the helper runs.
        shutil.rmtree(self.replacement)
        result = subprocess.run(
            ["/bin/sh", str(self.script), str(self.target), str(self.stage),
             "99999999", "test-token"],
            capture_output=True, text=True, timeout=20,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.target / "old.txt").exists())
        self.assert_lock_available()

    def test_initial_exchange_failure_reopens_original(self):
        self.staged_swap.unlink()
        code, _ = self.run_helper("exit 1\n")
        self.assertNotEqual(code, 0)
        self.assertTrue((self.target / "old.txt").exists())
        self.assertTrue((self.stage / "failure.txt").exists())
        self.assertTrue((self.stage / "reopened").exists())
        self.assertTrue(self.replacement.exists())
        self.assert_lock_available()

    def test_interruption_after_exchange_keeps_both_bundles(self):
        command = self.helper_command('touch "$2/new-started"\nexec sleep 20\n')
        with self.lock.open("a+b") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            process = subprocess.Popen(command, stdin=lock, start_new_session=True)
        try:
            deadline = time.monotonic() + 10
            while not (self.stage / "new-started").exists():
                self.assertIsNone(process.poll())
                self.assertLess(time.monotonic(), deadline, "replacement did not start")
                time.sleep(0.02)
            with self.assertRaises(BlockingIOError):
                self.assert_lock_available()
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)

        self.assertEqual((self.target / "new.txt").read_text(), "new")
        self.assertEqual((self.replacement / "old.txt").read_text(), "old")
        self.assert_lock_available()

    def test_old_process_timeout_preserves_running_original(self):
        script = self.script.read_text(encoding="utf-8")
        script = script.replace("old_pid=$3", "old_pid=$$")
        script = script.replace('[ "$attempts" -ge 60 ]', '[ "$attempts" -ge 2 ]')
        self.script.write_text(script, encoding="utf-8")
        code, _ = self.run_helper("exit 1\n")
        self.assertNotEqual(code, 0)
        self.assertTrue((self.target / "old.txt").exists())
        self.assertTrue((self.stage / "failure.txt").exists())
        self.assertFalse((self.stage / "reopened").exists())
        self.assertTrue(self.replacement.exists())
        self.assert_lock_available()


if __name__ == "__main__":
    unittest.main()
