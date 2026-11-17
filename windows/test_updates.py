"""Run with python -m unittest discover -s windows -p 'test_updates.py'."""
import hashlib
import io
import json
from pathlib import Path
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

import updates


def release(tag, **overrides):
    value = {
        "tag_name": tag,
        "draft": False,
        "prerelease": False,
        "html_url": f"https://github.com/YenningC/Yecatz/releases/tag/{tag}",
        "assets": [{
            "name": updates.ASSET_NAME,
            "state": "uploaded",
            "browser_download_url": f"https://github.com/YenningC/Yecatz/releases/download/{tag}/{updates.ASSET_NAME}",
        }],
    }
    value.update(overrides)
    return value


class ReleaseTests(unittest.TestCase):
    def test_accepts_windows_tag_and_legacy_installed_versions(self):
        self.assertEqual(updates.version("1.2.3_W", True), (1, 2, 3))
        self.assertEqual(updates.version("v1.2.3_W", True), (1, 2, 3))
        self.assertEqual(updates.version("0.1.2"), (0, 1, 2))
        self.assertEqual(updates.version("1.2"), (1, 2, 0))
        self.assertEqual(updates.version("1"), (1, 0, 0))

    def test_release_tags_are_platform_specific_stable_three_component(self):
        for tag in ("1.2.3_M", "1.2.3", "1.2_W", "1.2.3_W-beta", "1.2.3-beta_W", "１.２.３_W", None):
            with self.subTest(tag=tag):
                self.assertIsNone(updates.version(tag, True))

    def test_highest_numeric_windows_release_wins(self):
        releases = [release("99.0.0_M"), release("1.9.0_W"), release("1.10.0_W"), release("1.2.0_W")]
        self.assertEqual(updates.select_release(releases, "1.0.0")["tag_name"], "1.10.0_W")

    def test_ignores_drafts_prereleases_generic_tags_missing_assets(self):
        releases = [release("2.0.0_W", draft=True), release("3.0.0_W", prerelease=True),
                    release("4.0.0"), release("5.0.0_W", assets=[]), release("1.0.1_W")]
        self.assertEqual(updates.select_release(releases, "1.0.0")["tag_name"], "1.0.1_W")

    def test_equal_or_lower_versions_do_not_update(self):
        self.assertIsNone(updates.select_release([release("1.0.0_W"), release("0.9.0_W")], "v1.0.0_W"))

    def test_release_and_asset_urls_must_match_repository_tag(self):
        for url in ("http://github.com/YenningC/Yecatz/releases/tag/2.0.0_W",
                    "https://github.com.evil.test/YenningC/Yecatz/releases/tag/2.0.0_W",
                    "https://github.com/Someone/Else/releases/tag/2.0.0_W",
                    "https://github.com/YenningC/Yecatz/releases/tag/3.0.0_W"):
            with self.subTest(url=url):
                self.assertIsNone(updates.select_release([release("2.0.0_W", html_url=url)], "1.0.0"))
        item = release("2.0.0_W")
        item["assets"][0]["browser_download_url"] = "https://example.com/app.zip"
        self.assertIsNone(updates.select_release([item], "1.0.0"))

    def test_paginates_beyond_one_hundred_releases(self):
        calls = []

        def get_json(url, headers):
            calls.append(url)
            return [release("9.0.0_M")] * 100 if len(calls) == 1 else [release("2.0.0_W")]

        self.assertEqual(updates.check_update("1.0.0", get_json)["tag_name"], "2.0.0_W")
        self.assertEqual(len(calls), 2)
        self.assertIn("page=2", calls[1])

    def test_invalid_api_response_and_installed_version_fail(self):
        with self.assertRaises(ValueError):
            updates.check_update("1.0.0", lambda *args, **kwargs: {"message": "rate limited"})
        with self.assertRaises(ValueError):
            updates.select_release([], "broken")


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="yecatz-archive-test-")
        self.root = Path(self.directory.name)
        self.archive = self.root / "package.zip"
        self.destination = self.root / "extracted"

    def tearDown(self):
        self.directory.cleanup()

    def make_archive(self, extra=(), version="2.0.0_W", executable=b"MZstub", backslashes=False):
        entries = [
            ("Yecatz/Yecatz.exe", executable),
            ("Yecatz/_internal/runtime.dll", b"runtime"),
            ("Yecatz/update-version.json", json.dumps({"version": version})),
        ]
        with zipfile.ZipFile(self.archive, "w") as archive:
            for name, value in entries + list(extra):
                if backslashes and isinstance(name, str):
                    name = name.replace("/", "\\")
                archive.writestr(name, value)

    def test_valid_archive_and_windows_archive_separators(self):
        self.make_archive(backslashes=True)
        app = updates.extract_package(self.archive, self.destination, "2.0.0_W")
        self.assertEqual((app / "Yecatz.exe").read_bytes(), b"MZstub")
        self.assertEqual((app / "_internal/runtime.dll").read_bytes(), b"runtime")

    def test_archive_rejects_escaping_absolute_reserved_and_alternate_stream_paths(self):
        names = ["Yecatz/../../escaped.txt", "/Yecatz/file", "C:/Yecatz/file", "Yecatz/file:stream",
                 "Yecatz/CON.txt", "Yecatz/file.", "Yecatz/file ", "Other/app.exe"]
        for name in names:
            with self.subTest(name=name):
                self.make_archive([(name, b"bad")])
                with self.assertRaises(ValueError):
                    updates.extract_package(self.archive, self.destination, "2.0.0_W")
                self.assertFalse(self.destination.exists())

    def test_rejects_symlinks(self):
        link = zipfile.ZipInfo("Yecatz/_internal/link")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.make_archive([(link, "../../outside")])
        with self.assertRaises(ValueError):
            updates.extract_package(self.archive, self.destination, "2.0.0_W")

    def test_rejects_case_insensitive_duplicate(self):
        self.make_archive([("Yecatz/yecatz.EXE", b"MZother")])
        with self.assertRaises(ValueError):
            updates.extract_package(self.archive, self.destination, "2.0.0_W")

    def test_rejects_package_entries_that_could_overwrite_user_files(self):
        self.make_archive([("Yecatz/notes.txt", b"unexpected")])
        with self.assertRaises(ValueError):
            updates.extract_package(self.archive, self.destination, "2.0.0_W")
        self.assertFalse(self.destination.exists())

    def test_rejects_mismatched_version(self):
        self.make_archive(version="3.0.0_W")
        with self.assertRaises(ValueError):
            updates.extract_package(self.archive, self.destination, "2.0.0_W")

    def test_rejects_non_windows_version(self):
        self.make_archive(version="2.0.0_M")
        with self.assertRaises(ValueError):
            updates.extract_package(self.archive, self.destination, "2.0.0_W")

    def test_rejects_non_executable_payload(self):
        self.make_archive(executable=b"wrong format")
        with self.assertRaises(ValueError):
            updates.extract_package(self.archive, self.destination, "2.0.0_W")

    def test_rejects_malformed_zip(self):
        self.archive.write_bytes(b"not a zip")
        with self.assertRaises(zipfile.BadZipFile):
            updates.extract_package(self.archive, self.destination, "2.0.0_W")


class DownloadTests(unittest.TestCase):
    def test_download_checks_size_digest_and_tls(self):
        payload = b"downloaded zip bytes"
        asset = {"size": len(payload), "browser_download_url": "https://github.com/package.zip",
                 "digest": "sha256:" + hashlib.sha256(payload).hexdigest()}
        scenarios = [({}, "https://release-assets.githubusercontent.com/package", None),
                     ({"size": len(payload) + 1}, "https://example.test/package", ValueError),
                     ({"size": len(payload) - 1}, "https://example.test/package", ValueError),
                     ({"digest": "sha256:" + "0" * 64}, "https://example.test/package", ValueError),
                     ({}, "http://example.test/package", ValueError)]
        for overrides, url, failure in scenarios:
            with self.subTest(overrides=overrides, url=url), tempfile.TemporaryDirectory() as directory:
                response = io.BytesIO(payload)
                response.url = url
                output = Path(directory) / "download.zip"
                with patch.object(updates.urllib.request, "urlopen", return_value=response):
                    if failure:
                        with self.assertRaises(failure):
                            updates.download_package(asset | overrides, output)
                    else:
                        updates.download_package(asset, output)
                        self.assertEqual(output.read_bytes(), payload)


class TransactionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="yecatz-transaction-test-")
        self.root = Path(self.directory.name).resolve()
        self.target = self.root / "Yecatz"
        self.target.mkdir()
        (self.target / "Yecatz.exe").write_bytes(b"MZold")
        (self.target / "_internal").mkdir()
        (self.target / "notes.txt").write_text("user notes")
        (self.target / "user-files").mkdir()
        (self.target / "user-files/example.txt").write_text("personal content")
        self.resource = self.root / "resource"
        self.resource.mkdir()
        (self.resource / "install-update.ps1").write_text("# fixture helper")
        self.frozen = patch.object(updates.sys, "frozen", True, create=True)
        self.executable = patch.object(updates.sys, "executable", str(self.target / "Yecatz.exe"))
        self.frozen.start()
        self.executable.start()
        self.transaction = updates.transaction_path(self.target)

    def tearDown(self):
        self.executable.stop()
        self.frozen.stop()
        self.directory.cleanup()

    @staticmethod
    def write_download(asset, destination):
        with zipfile.ZipFile(destination, "w") as package:
            package.writestr("Yecatz/Yecatz.exe", b"MZnew")
            package.writestr("Yecatz/_internal/runtime.dll", b"runtime")
            package.writestr("Yecatz/update-version.json", json.dumps({"version": "2.0.0_W"}))

    def write_transaction(self):
        self.transaction.mkdir()
        config = {"target": str(self.target), "tag": "2.0.0_W", "token": "fixture"}
        (self.transaction / "config.json").write_text(json.dumps(config), encoding="utf-8")

    def test_preparation_preserves_user_files_and_running_installation(self):
        def launch(transaction):
            (transaction / "helper-ready").write_text("ready")
            return SimpleNamespace(pid=12345)

        with patch.object(updates, "download_package", side_effect=self.write_download), \
                patch.object(updates, "launch_helper", side_effect=launch):
            updates.prepare_update({"asset": {}, "tag_name": "2.0.0_W"}, self.resource)
        incoming = self.transaction / "Yecatz"
        self.assertEqual((self.target / "notes.txt").read_text(), "user notes")
        self.assertEqual((self.target / "user-files/example.txt").read_text(), "personal content")
        self.assertFalse((incoming / "notes.txt").exists())
        self.assertFalse((incoming / "user-files").exists())
        self.assertIn("-Recover", (self.transaction / updates.RECOVERY_NAME).read_text())
        self.assertEqual((self.target / "Yecatz.exe").read_bytes(), b"MZold")
        self.assertEqual((incoming / "Yecatz.exe").read_bytes(), b"MZnew")

    def test_download_failure_removes_only_staging(self):
        with patch.object(updates, "download_package", side_effect=OSError("network error")):
            with self.assertRaises(OSError):
                updates.prepare_update({"asset": {}, "tag_name": "2.0.0_W"}, self.resource)
        self.assertFalse(self.transaction.exists())
        self.assertEqual((self.target / "Yecatz.exe").read_bytes(), b"MZold")
        self.assertEqual((self.target / "notes.txt").read_text(), "user notes")

    def test_initialization_never_exposes_transaction_without_complete_config(self):
        with patch.object(updates.os, "fsync", side_effect=OSError("disk error")), \
                patch.object(updates, "download_package") as download:
            with self.assertRaisesRegex(OSError, "disk error"):
                updates.prepare_update({"asset": {}, "tag_name": "2.0.0_W"}, self.resource)
        download.assert_not_called()
        self.assertFalse(self.transaction.exists())
        self.assertEqual(list(self.root.glob(".yecatz-prepare-*")), [])

    def test_startup_ack_requires_installed_marker_and_matching_version(self):
        self.write_transaction()
        updates.confirm_startup("2.0.0_W")
        self.assertFalse((self.transaction / "ready.json").exists())
        (self.transaction / "installed").write_text("installed")
        updates.confirm_startup("1.0.0_W")
        self.assertFalse((self.transaction / "ready.json").exists())
        updates.confirm_startup("2.0.0_W")
        ack = json.loads((self.transaction / "ready.json").read_text())
        self.assertEqual(ack["token"], "fixture")
        self.assertEqual(ack["tag"], "2.0.0_W")

    def test_retry_clears_completed_rollback(self):
        self.write_transaction()
        (self.transaction / "result.txt").write_text("rolled back")
        (self.transaction / "applying").touch()
        (self.transaction / "rolled-back").touch()
        (self.transaction / "previous").mkdir()
        updates.clear_finished_transaction(self.transaction, self.target)
        self.assertFalse(self.transaction.exists())
        self.assertTrue((self.target / "Yecatz.exe").exists())

    def test_retry_releases_active_name_before_recursive_cleanup(self):
        self.write_interrupted_preparation()
        with patch.object(updates, "process_running", return_value=False), \
                patch.object(updates.shutil, "rmtree") as remove:
            updates.clear_finished_transaction(self.transaction, self.target)
        self.assertFalse(self.transaction.exists())
        retired = remove.call_args.args[0]
        self.assertEqual(retired.parent, self.transaction.parent)
        self.assertTrue((retired / "config.json").is_file())

    def test_retry_retains_uncertain_old_backup(self):
        self.write_transaction()
        (self.transaction / "result.txt").write_text("recovery incomplete")
        (self.transaction / "previous").mkdir()
        (self.transaction / "previous/important.txt").write_text("keep")
        updates.clear_finished_transaction(self.transaction, self.target)
        self.assertTrue((self.transaction / "previous/important.txt").exists())

    def test_retry_cleans_acknowledged_success_after_cleanup_failure(self):
        self.write_transaction()
        (self.target / "update-version.json").write_text(json.dumps({"version": "2.0.0_W"}))
        (self.transaction / "result.txt").write_text("cleanup failed")
        (self.transaction / "previous").mkdir()
        (self.transaction / "applying").touch()
        (self.transaction / "committed").touch()
        updates.clear_finished_transaction(self.transaction, self.target)
        self.assertFalse(self.transaction.exists())

    def test_retry_preserves_backup_for_mismatched_target_version_or_token(self):
        self.write_transaction()
        (self.transaction / "result.txt").write_text("cleanup failed")
        (self.transaction / "previous").mkdir()
        (self.transaction / "previous/old.exe").write_bytes(b"MZold")
        (self.transaction / "installed").write_text("installed")
        scenarios = [
            (str(self.root / "different"), "2.0.0_W", "fixture"),
            (str(self.target), "1.0.0_W", "fixture"),
            (str(self.target), "2.0.0_W", "wrong"),
        ]
        for target, current, token in scenarios:
            with self.subTest(target=target, current=current, token=token):
                config = {"target": target, "tag": "2.0.0_W", "token": "fixture"}
                (self.transaction / "config.json").write_text(json.dumps(config), encoding="utf-8")
                (self.target / "update-version.json").write_text(json.dumps({"version": current}))
                (self.transaction / "ready.json").write_text(json.dumps({"token": token}))
                updates.clear_finished_transaction(self.transaction, self.target)
                self.assertEqual((self.transaction / "previous/old.exe").read_bytes(), b"MZold")

    def write_interrupted_preparation(self):
        self.write_transaction()
        config = {"target": str(self.target), "tag": "2.0.0_W", "token": "fixture", "phase": "preparing",
                  "parent_pid": 101, "helper_pid": 202}
        (self.transaction / "config.json").write_text(json.dumps(config), encoding="utf-8")
        (self.transaction / "package.zip").write_bytes(b"partial download")

    def test_interrupted_preparation_is_cleared_after_processes_exit(self):
        self.write_interrupted_preparation()
        with patch.object(updates, "process_running", return_value=False) as running:
            updates.clear_finished_transaction(self.transaction, self.target)
        self.assertFalse(self.transaction.exists())
        self.assertEqual([call.args[0] for call in running.call_args_list], [101, 202])
        self.assertEqual((self.target / "Yecatz.exe").read_bytes(), b"MZold")

    def test_preparation_is_retained_while_parent_or_helper_is_alive(self):
        self.write_interrupted_preparation()
        for active_pid in (101, 202):
            with self.subTest(active_pid=active_pid), \
                    patch.object(updates, "process_running", side_effect=lambda pid: pid == active_pid):
                updates.clear_finished_transaction(self.transaction, self.target)
                self.assertTrue((self.transaction / "package.zip").exists())

    def test_interrupted_installation_backup_is_retained(self):
        self.write_interrupted_preparation()
        (self.transaction / "previous").mkdir()
        (self.transaction / "applying").touch()
        (self.transaction / "previous/old.exe").write_bytes(b"MZold")
        with patch.object(updates, "process_running", return_value=False):
            updates.clear_finished_transaction(self.transaction, self.target)
        self.assertEqual((self.transaction / "previous/old.exe").read_bytes(), b"MZold")

    def test_interrupted_installed_stage_is_retained(self):
        self.write_interrupted_preparation()
        (self.transaction / "installed").write_text("installed")
        with patch.object(updates, "process_running", return_value=False):
            updates.clear_finished_transaction(self.transaction, self.target)
        self.assertTrue((self.transaction / "installed").exists())


if __name__ == "__main__":
    unittest.main()
