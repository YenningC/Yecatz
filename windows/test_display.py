"""Regression checks for the transparent window's screen-change recovery."""
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
import yecatz
from PySide6.QtCore import QEvent
from PySide6.QtGui import QColor, QImage
from PySide6.QtTest import QSignalSpy


class DisplayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = yecatz.QApplication.instance() or yecatz.QApplication([])
        cls.assets = Path(os.environ.get("YECATZ_TEST_ASSETS", "build/verification-assets")).resolve()
        if "YECATZ_TEST_ASSETS" not in os.environ and not (cls.assets / "cat.png").exists():
            temporary = TemporaryDirectory()
            cls.addClassCleanup(temporary.cleanup)
            cls.assets = Path(temporary.name)
            sprite = QImage(80, 24, QImage.Format.Format_ARGB32)
            sprite.fill(QColor("#325874"))
            for name in ("cat.png", "cat-blink.png", "cat-entry.png", "tie-status.png"):
                if not sprite.save(str(cls.assets / name)):
                    raise RuntimeError(f"Could not create display test asset {name}")

    def setUp(self):
        with patch.object(yecatz, "ASSETS", self.assets), patch.object(yecatz, "load_settings", return_value={}), \
                patch.object(yecatz.Pet, "check_update", lambda self, manual=False: None):
            self.pet = yecatz.Pet()
        self.pet.anim.stop()
        self.pet.hourly.stop()
        self.pet.entering = False
        self.pet.move(30, 30)
        self.app.processEvents()
        self.pet.display_refresh.stop()

    def tearDown(self):
        self.pet.display_refresh.stop()
        self.pet.tray.hide()
        self.pet.close()
        self.pet.deleteLater()
        self.app.processEvents()

    def test_refresh_preserves_position_size_and_complete_image(self):
        before = self.pet.grab().toImage()
        position = self.pet.pos()
        for _ in range(5):
            self.pet.refresh_display_surface()
        self.assertEqual(self.pet.pos(), position)
        self.assertEqual((self.pet.width(), self.pet.height()), (220, 265))
        self.assertEqual(self.pet.grab().toImage(), before)

    def test_dpi_event_schedules_refresh(self):
        self.app.sendEvent(self.pet, QEvent(QEvent.Type.DevicePixelRatioChange))
        self.assertTrue(self.pet.display_refresh.isActive())

    def test_tray_menu_show_refreshes_after_hidden_dpi_event(self):
        self.pet.hide()
        timeout = QSignalSpy(self.pet.display_refresh.timeout)
        self.app.sendEvent(self.pet, QEvent(QEvent.Type.DevicePixelRatioChange))
        self.assertTrue(timeout.wait(1000))
        self.assertFalse(self.pet.display_refresh.isActive())

        menu = self.pet.tray.contextMenu()
        show_action = next(action for action in menu.actions() if action.text() == "显示 Yecatz")
        show_action.trigger()

        self.assertTrue(self.pet.isVisible())
        self.assertTrue(self.pet.display_refresh.isActive())

    def test_refresh_waits_until_drag_finishes(self):
        self.pet.drag_start = self.pet.pos()
        self.pet.refresh_display_surface()
        self.assertTrue(self.pet.display_refresh.isActive())
        self.assertEqual((self.pet.width(), self.pet.height()), (220, 265))
        self.pet.drag_start = None


if __name__ == "__main__":
    unittest.main()
