"""Offline build-input tests; no claim of a running GNOME session or GPU."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
KARGS = Path("usr/lib/bootc/kargs.d/60-ttm.toml")


class TtmKargs(unittest.TestCase):
    def generate(self, root, pages="", pool=""):
        return subprocess.run(
            ["bash", "-eu", "-c", 'source "$1"; write_ttm_kargs "$2"',
             "test", str(ROOT / "build/ttm-kargs.sh"), str(root)],
            env={**os.environ, "TTM_PAGES_LIMIT": pages, "TTM_PAGE_POOL_SIZE": pool},
            capture_output=True, text=True, timeout=5,
        )

    def test_default_absent(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.generate(tmp).returncode, 0)
            self.assertFalse((Path(tmp) / "usr").exists())

    def test_configured_toml(self):
        for pages, pool in [("1", "2"), ("0", "2147483647"), ("12", ""), ("", "34")]:
            with self.subTest(pages=pages, pool=pool), tempfile.TemporaryDirectory() as tmp:
                self.assertEqual(self.generate(tmp, pages, pool).returncode, 0)
                parsed = tomllib.loads((Path(tmp) / KARGS).read_text())
                expected = []
                if pages:
                    expected.append(f"ttm.pages_limit={pages}")
                if pool:
                    expected.append(f"ttm.page_pool_size={pool}")
                self.assertEqual(parsed, {"kargs": expected})

    def test_invalid_inputs_leave_no_file(self):
        for bad in ["-1", "+1", "01", "0x10", "1.5", "1G", " 1", "1\n", "1 2",
                    '1"], kargs=["bad', "2147483648", "9" * 100, "$(false)"]:
            for name in ["pages", "pool"]:
                with self.subTest(bad=bad, name=name), tempfile.TemporaryDirectory() as tmp:
                    args = {"pages": "1", "pool": "2", name: bad}
                    result = self.generate(tmp, **args)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("decimal page count", result.stderr)
                    self.assertFalse((Path(tmp) / KARGS).exists())


@unittest.skipUnless(shutil.which("dconf") and shutil.which("gsettings"),
                     "dconf and GNOME schemas required; image test exercises this too")
class SuspendSettings(unittest.TestCase):
    def test_configuration_and_reversal(self):
        # The same inactive keyfile is used in local (users) and gdm databases.
        schema = "org.gnome.settings-daemon.plugins.power"
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            keydir = tmp / "db.d"
            keydir.mkdir()
            database = tmp / "db"
            profile = tmp / "profile"
            profile.write_text(f"user-db:user\nfile-db:{database}\n")
            env = {**os.environ, "DCONF_PROFILE": str(profile),
                   "XDG_CONFIG_HOME": str(tmp / "config")}

            def read():
                return [subprocess.check_output(
                    ["gsettings", "get", schema, f"sleep-inactive-{power}-type"],
                    env=env, text=True, timeout=5).strip() for power in ["ac", "battery"]]

            subprocess.run(["dconf", "compile", str(database), str(keydir)], check=True, timeout=5)
            baseline = read()
            keyfile = keydir / "60-no-auto-suspend"
            shutil.copyfile(ROOT / "custom/variants/desktop/no-auto-suspend.dconf", keyfile)
            subprocess.run(["dconf", "compile", str(database), str(keydir)], check=True, timeout=5)
            self.assertEqual(read(), ["'nothing'", "'nothing'"])
            keyfile.unlink()
            subprocess.run(["dconf", "compile", str(database), str(keydir)], check=True, timeout=5)
            self.assertEqual(read(), baseline)


if __name__ == "__main__":
    unittest.main()
