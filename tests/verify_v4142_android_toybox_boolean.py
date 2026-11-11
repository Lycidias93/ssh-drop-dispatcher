#!/usr/bin/env python3
"""Regression for Android Toybox-compatible WebUI boolean settings parsing."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sdd_v4142_build", ROOT / "tools/build_v4142_hotfix.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class WebUIAndroidBoolean(unittest.TestCase):
    def test_replaces_exact_legacy_gnu_alternation(self):
        src = "#!/system/bin/sh\n" + builder.ANDROID_BOOL_OLD_LINE + "\n"
        patched = builder.patch_android_toybox_boolean(src)
        self.assertEqual(patched.count(builder.ANDROID_BOOL_FIXED_LINE), 1)
        self.assertNotIn(r"\|", patched)
        self.assertEqual(patched.splitlines()[0], "#!/system/bin/sh")

    def test_fails_closed_on_missing_or_repeated_anchor(self):
        for src in ("not-a-webui-adapter\n", builder.ANDROID_BOOL_OLD_LINE + "\n" + builder.ANDROID_BOOL_OLD_LINE):
            with self.subTest(source_len=len(src)):
                with self.assertRaisesRegex(RuntimeError, "unexpected_webui_boolean_parser"):
                    builder.patch_android_toybox_boolean(src)

    def test_posix_shell_booleans_true_false_and_missing(self):
        body = (
            "json_extract_bool() {\n"
            "  key=$1\n"
            "  file=$2\n"
            + builder.ANDROID_BOOL_FIXED_LINE
            + "\n}\n"
            'json_extract_bool ntfy_enabled "$1"\n'
        )
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "config.json"
            for payload, expected in (
                ('{"ntfy_enabled":true,"ntfy_priority":"low"}', "true"),
                ('{"ntfy_enabled":false,"ntfy_priority":"low"}', "false"),
                ('{"ntfy_priority":"low"}', ""),
            ):
                with self.subTest(payload=payload):
                    path.write_text(payload + "\n")
                    proc = subprocess.run(
                        ["sh", "-c", body, "sh", str(path)],
                        capture_output=True, text=True, check=True,
                    )
                    self.assertEqual(proc.stdout.strip(), expected)
                    self.assertEqual(proc.stderr, "")


if __name__ == "__main__":
    unittest.main()
