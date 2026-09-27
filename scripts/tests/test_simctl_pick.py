"""Тесты выбора симулятора (scripts/simctl_pick.py) на сохранённом выводе `simctl list -j`."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import simctl_pick as sp  # noqa: E402


def devtype(name):
    return {"name": name, "identifier": "type." + name.replace(" ", "-")}


RUNTIME_26 = {
    "platform": "iOS", "identifier": "rt.iOS-26-5", "version": "26.5", "isAvailable": True, "name": "iOS 26.5",
    "supportedDeviceTypes": [devtype(n) for n in (
        "iPhone 17 Pro", "iPhone 17 Pro Max", "iPhone 17e", "iPhone Air", "iPhone SE (3rd generation)",
        "iPad (A16)", "iPad mini (A17 Pro)", "iPad Pro 11-inch (M5)", "iPad Pro 13-inch (M5)")],
}
RUNTIME_17 = {
    "platform": "iOS", "identifier": "rt.iOS-17-5", "version": "17.5", "isAvailable": True, "name": "iOS 17.5",
    "supportedDeviceTypes": [devtype(n) for n in ("iPhone 15", "iPhone 15 Pro Max", "iPhone SE (3rd generation)",
                                                  "iPad (10th generation)")],
}
RUNTIME_16_2 = {
    "platform": "iOS", "identifier": "rt.iOS-16-2", "version": "16.2", "isAvailable": True, "name": "iOS 16.2",
    "supportedDeviceTypes": [devtype("iPhone 14")],
}
TVOS = {"platform": "tvOS", "identifier": "rt.tvOS-26-5", "version": "26.5", "isAvailable": True,
        "supportedDeviceTypes": []}

DATA = {
    "runtimes": [RUNTIME_26, RUNTIME_17, RUNTIME_16_2, TVOS],
    "devices": {"rt.iOS-26-5": [{"udid": "EXISTING-17PRO", "name": "iPhone 17 Pro",
                                 "deviceTypeIdentifier": "type.iPhone-17-Pro", "isAvailable": True}]},
}


class PickTests(unittest.TestCase):
    def setUp(self):
        self.created = []

    def create(self, name, type_id, runtime_id):
        self.created.append((name, type_id, runtime_id))
        return "NEW-%d" % len(self.created)

    def pick(self, kind, want="latest", **kw):
        return sp.pick(kind, want, data=DATA, create=self.create, **kw)

    def test_kinds_on_latest_runtime(self):
        expected = {
            "iphone-small": "iPhone SE (3rd generation)",
            "iphone-big": "iPhone 17 Pro Max",
            "iphone": "iPhone 17 Pro",
            "ipad": "iPad (A16)",
            "ipad-mini": "iPad mini (A17 Pro)",
            "ipad-13": "iPad Pro 13-inch (M5)",
        }
        for kind, name in expected.items():
            udid, got, version = self.pick(kind)
            self.assertEqual((got, version), (name, "26.5"), kind)

    def test_reuses_existing_device(self):
        udid, _, _ = self.pick("iphone")
        self.assertEqual(udid, "EXISTING-17PRO")
        self.assertEqual(self.created, [])

    def test_creates_missing_device(self):
        udid, _, _ = self.pick("iphone-small")
        self.assertEqual(udid, "NEW-1")
        self.assertEqual(self.created[0][1:], ("type.iPhone-SE-(3rd-generation)", "rt.iOS-26-5"))

    def test_oldest_respects_minimum_ios(self):
        _, name, version = self.pick("iphone-small", "oldest")
        self.assertEqual((name, version), ("iPhone SE (3rd generation)", "17.5"))

    def test_specific_version_and_fallback_model(self):
        _, name, version = self.pick("ipad", "17")
        self.assertEqual((name, version), ("iPad (10th generation)", "17.5"))
        _, name, _ = self.pick("iphone-big", "17.5")
        self.assertEqual(name, "iPhone 15 Pro Max")

    def test_missing_runtime(self):
        with self.assertRaises(sp.PickError) as ctx:
            self.pick("iphone", "18.0")
        self.assertIn("17.5", str(ctx.exception))

    def test_download_when_allowed(self):
        downloads = []
        runtime_18 = dict(RUNTIME_17, identifier="rt.iOS-18-0", version="18.0")
        loads = [dict(DATA, runtimes=DATA["runtimes"] + [runtime_18])]
        sp.pick("iphone-small", "18.0", data=DATA, allow_download=True, create=self.create,
                load=lambda: loads[0], download=downloads.append)
        self.assertEqual(downloads, ["18.0"])

    def test_exact_model(self):
        _, name, _ = self.pick("iphone", exact="iPhone Air")
        self.assertEqual(name, "iPhone Air")
        with self.assertRaises(sp.PickError):
            self.pick("iphone", exact="iPhone 99")

    def test_unknown_kind(self):
        with self.assertRaises(sp.PickError):
            self.pick("watch")


if __name__ == "__main__":
    unittest.main()
