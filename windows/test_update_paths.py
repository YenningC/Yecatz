"""Protect actual Windows user folders before whole-directory updates."""
import os
from pathlib import Path
import unittest
from unittest.mock import patch

import updates


@unittest.skipUnless(os.name == "nt", "Windows known-folder registry tests")
class ProtectedInstallRootsTests(unittest.TestCase):
    def test_defaults_remain_protected_when_registry_is_unavailable(self):
        target = Path("D:/Apps/Yecatz")
        with patch("winreg.OpenKey", side_effect=OSError):
            roots = updates.protected_install_roots(target)
        self.assertIn(Path("D:/"), roots)
        self.assertIn(Path.home().resolve(), roots)
        for name in ("Desktop", "Documents", "Downloads"):
            self.assertIn((Path.home() / name).resolve(), roots)

    def test_redirected_and_expanded_folders_are_protected(self):
        values = {
            "Desktop": r"%YECATZ_TEST_PROFILE%\OneDrive\Desktop",
            "Personal": r"D:\User documents",
            "{374DE290-123F-4565-9164-39C4925E467B}": r"D:\Downloads",
        }
        with (
            patch("winreg.OpenKey"),
            patch("winreg.QueryValueEx", side_effect=lambda key, name: (values[name], 2)),
            patch.dict(os.environ, {"YECATZ_TEST_PROFILE": r"C:\Users\Example"}),
        ):
            roots = updates.protected_install_roots(Path("C:/Apps/Yecatz"))
        self.assertIn(Path("C:/Users/Example/OneDrive/Desktop"), roots)
        self.assertIn(Path("D:/User documents"), roots)
        self.assertIn(Path("D:/Downloads"), roots)

    def test_missing_registry_value_does_not_hide_other_folders(self):
        def query(key, name):
            if name == "Personal":
                return r"D:\Documents", 1
            raise FileNotFoundError(name)

        with patch("winreg.OpenKey"), patch("winreg.QueryValueEx", side_effect=query):
            roots = updates.protected_install_roots(Path("C:/Apps/Yecatz"))
        self.assertIn(Path("D:/Documents"), roots)

    def test_prepare_refuses_redirected_desktop_before_downloading(self):
        desktop = Path("C:/Users/Example/OneDrive/Desktop")
        with (
            patch("winreg.OpenKey"),
            patch("winreg.QueryValueEx", return_value=(str(desktop), 1)),
            patch.object(updates.sys, "frozen", True, create=True),
            patch.object(updates.sys, "executable", str(desktop / "Yecatz.exe")),
            patch.object(updates, "download_package") as download,
        ):
            with self.assertRaisesRegex(ValueError, "独立的程序目录"):
                updates.prepare_update({}, Path("unused"))
            download.assert_not_called()


if __name__ == "__main__":
    unittest.main()
