import tempfile
import unittest
from pathlib import Path

from wrt_core.builder.config import BuildConfig, PackagesConfig
from wrt_core.builder.packages import PackageManager


class DummyLogger:
    def __getattr__(self, _name):
        return lambda _msg: None


class PackageManagerRemoveTests(unittest.TestCase):
    def test_remove_unwanted_preserves_custom_feed_replacement(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base_path = root / "wrt_core"
            build_dir = root / "action_build"

            official = build_dir / "feeds" / "luci" / "applications" / "luci-app-homeproxy"
            official_link = build_dir / "package" / "feeds" / "luci" / "luci-app-homeproxy"
            custom_src = build_dir / "custom_feed" / "luci-app-homeproxy"
            custom_link = build_dir / "package" / "feeds" / "custom_feed" / "luci-app-homeproxy"

            for path in (official, official_link, custom_src, custom_link):
                path.mkdir(parents=True, exist_ok=True)
                (path / "Makefile").write_text("PKG_NAME:=luci-app-homeproxy\n", encoding="utf-8")

            config = BuildConfig(packages=PackagesConfig(remove={
                "luci_apps": ["luci-app-homeproxy"],
            }))
            manager = PackageManager(config, base_path, build_dir, DummyLogger())

            self.assertTrue(manager.remove_unwanted())

            self.assertFalse(official.exists())
            self.assertFalse(official_link.exists())
            self.assertTrue(custom_src.exists())
            self.assertTrue(custom_link.exists())


if __name__ == "__main__":
    unittest.main()
