import pathlib
import plistlib
import runpy
import subprocess
import unittest


detach = runpy.run_path(str(pathlib.Path(__file__).resolve().parents[1] / "scripts/detach-image.py"))["detach_image"]


class DetachImageTests(unittest.TestCase):
    def setUp(self):
        self.image = pathlib.Path("/tmp/kaze-private/writable.dmg")
        self.attached = True
        self.statuses = [0]
        self.calls = []
        self.waits = []
        self.disappear_on_error = False

    def fake_run(self, arguments, capture_output):
        self.calls.append(arguments)
        if arguments == ["hdiutil", "info", "-plist"]:
            images = [{"image-path": "/tmp/other.dmg", "system-entities": [{"dev-entry": "/dev/disk99"}]}]
            if self.attached:
                images.append({"image-path": str(self.image), "system-entities": [{"dev-entry": "/dev/disk42"}]})
            return subprocess.CompletedProcess(arguments, 0, plistlib.dumps({"images": images}), b"")
        self.assertEqual(arguments, ["hdiutil", "detach", "-force", "/dev/disk42"])
        status = self.statuses.pop(0)
        if status == 0 or self.disappear_on_error:
            self.attached = False
        return subprocess.CompletedProcess(arguments, status, b"", b"Resource busy" if status else b"")

    def invoke(self):
        detach(self.image, run=self.fake_run, wait=self.waits.append)

    def test_busy_device_is_retried(self):
        self.statuses = [16, 16, 0]
        self.invoke()
        self.assertFalse(self.attached)
        self.assertEqual(self.waits, [2, 2])

    def test_error_after_successful_ejection_is_accepted(self):
        self.statuses = [16]
        self.disappear_on_error = True
        self.invoke()
        self.assertFalse(self.attached)
        self.assertEqual(len([call for call in self.calls if call[1] == "detach"]), 1)

    def test_missing_image_does_not_touch_another_disk(self):
        self.attached = False
        self.invoke()
        self.assertEqual(self.calls, [["hdiutil", "info", "-plist"]])

    def test_persistent_failure_is_reported(self):
        self.statuses = [16] * 5
        with self.assertRaisesRegex(RuntimeError, "Resource busy"):
            self.invoke()
        self.assertTrue(self.attached)
        self.assertEqual(len(self.waits), 4)


if __name__ == "__main__":
    unittest.main()
