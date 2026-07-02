import tempfile
import unittest
from pathlib import Path

from wrt_core.builder.config import BuildConfig
from wrt_core.builder.feeds import FeedManager


class DummyLogger:
    def __getattr__(self, _name):
        return lambda _msg: None


class FeedManagerPackageFixTests(unittest.TestCase):
    def test_fix_xray_allow_insecure_patch_matches_xray_26_6_27_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base_path = root / "wrt_core"
            build_dir = root / "action_build"
            custom_feed = build_dir / "custom_feed"
            xray_patches = custom_feed / "xray-core" / "patches"
            xray_patches.mkdir(parents=True)
            allow_patch = xray_patches / "AllowInsecure.patch"
            allow_patch.write_text(
                """--- a/infra/conf/transport_internet.go
+++ b/infra/conf/transport_internet.go
@@ -14,7 +14,6 @@ import (
 	"strconv"
 	"strings"
 	"syscall"
-	"time"
@@ -699,12 +698,7 @@ func (c *TLSConfig) Build() (proto.Message, error) {
 	config.MasterKeyLog = c.MasterKeyLog
 
 	if c.AllowInsecure {
-		if time.Now().After(time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)) {
-			return nil, errors.PrintRemovedFeatureError(`"allowInsecure"`, `"pinnedPeerCertSha256"`)
-		} else {
-			errors.LogWarning(context.Background(), `old warning`)
-			config.AllowInsecure = true
-		}
+		config.AllowInsecure = true
 	}
""",
                encoding="utf-8",
            )

            manager = FeedManager(BuildConfig(), base_path, build_dir, DummyLogger())
            manager._fix_xray_allow_insecure_patch(custom_feed)

            self.assertNotIn(b"\r\n", allow_patch.read_bytes())
            fixed = allow_patch.read_text(encoding="utf-8")
            self.assertNotIn('"time"', fixed)
            self.assertNotIn("time.Now()", fixed)
            self.assertIn('errors.PrintRemovedFeatureError(`"allowInsecure"`, `"pinnedPeerCertSha256"(pcs) and "verifyPeerCertByName"(vcn)`)', fixed)
            self.assertIn("+\t\tconfig.AllowInsecure = true", fixed)
            self.assertIn('if c.PinnedPeerCertSha256 != "" {', fixed)
            self.assertIn('strings.SplitSeq(c.PinnedPeerCertSha256, ",")', fixed)
            self.assertIn("@@ -730,7 +730,7 @@ func (c *TLSConfig) Build()", fixed)


if __name__ == "__main__":
    unittest.main()
