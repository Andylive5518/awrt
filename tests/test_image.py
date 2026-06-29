import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, Mock

from wrt_core.builder.config import BuildConfig, KernelConfig
from wrt_core.builder.image import ImageManager


class DummyLogger:
    def __init__(self):
        self.messages = []
    def info(self, msg): self.messages.append(("info", msg))
    def ok(self, msg): self.messages.append(("ok", msg))
    def fail(self, msg): self.messages.append(("fail", msg))


class ImageManagerConfigTests(unittest.TestCase):
    def test_generate_config_writes_combined_config_and_runs_defconfig_noninteractive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base_path = root / "wrt_core"
            build_dir = root / "action_build"
            (base_path / "deconfig").mkdir(parents=True)
            build_dir.mkdir()
            (base_path / "deconfig" / "base.config").write_text("CONFIG_TARGET_x86=y\n", encoding="utf-8")
            (base_path / "deconfig" / "extra.config").write_text("CONFIG_PACKAGE_htop=y\n", encoding="utf-8")

            config = BuildConfig(kernel_config=KernelConfig(
                base="deconfig/base.config",
                fragments=["deconfig/extra.config"],
            ))
            manager = ImageManager(config, base_path, build_dir, DummyLogger())

            completed = Mock(returncode=0, stdout="", stderr="")
            with patch("wrt_core.builder.image.subprocess.run", return_value=completed) as run:
                self.assertTrue(manager.generate_config())

            self.assertEqual(
                (build_dir / ".config").read_text(encoding="utf-8"),
                "CONFIG_TARGET_x86=y\nCONFIG_PACKAGE_htop=y\n",
            )
            run.assert_called_once()
            args, kwargs = run.call_args
            self.assertEqual(args[0], ["make", "defconfig"])
            self.assertEqual(kwargs["cwd"], str(build_dir))
            self.assertEqual(kwargs["env"]["TERM"], "xterm")


if __name__ == "__main__":
    unittest.main()
