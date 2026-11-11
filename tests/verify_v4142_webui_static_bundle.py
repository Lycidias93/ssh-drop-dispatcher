#!/usr/bin/env python3
"""Release gate: SDD overlays must use only routes served by pinned WebUI Core."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sdd_v4142_build", ROOT / "tools/build_v4142_hotfix.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

class WebUIStaticBundle(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sdd-webui-static-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "webroot"
        self.root.mkdir()
        (self.root / "index.html").write_text(
            '<link rel="stylesheet" href="app.css">\n'
            '  <link rel="stylesheet" href="sdd-ui.css">\n'
            '<script src="app.js"></script>\n'
            '  <script src="sdd-ui.js"></script>\n',
            encoding="utf-8",
        )
        (self.root / "app.css").write_bytes(b"body { color: black; }\n")
        (self.root / "sdd-ui.css").write_bytes(b".sdd { display: block; }\n")
        (self.root / "app.js").write_bytes(b'(() => { console.log("core"); })();\n')
        (self.root / "sdd-ui.js").write_bytes(b'(() => { console.log("sdd"); })();\n')

    def test_only_core_served_css_js_paths_remain(self):
        builder.bundle_webui_assets(self.root.parent)
        page = (self.root / "index.html").read_text()
        self.assertIn('href="app.css"', page)
        self.assertIn('src="app.js"', page)
        self.assertNotIn('href="sdd-ui.css"', page)
        self.assertNotIn('src="sdd-ui.js"', page)
        self.assertTrue((self.root / "app.css").read_bytes().endswith((self.root / "sdd-ui.css").read_bytes() + b"\n"))
        self.assertTrue((self.root / "app.js").read_bytes().endswith((self.root / "sdd-ui.js").read_bytes() + b"\n"))
        self.assertEqual((self.root / "app.js").read_text().count("})();"), 2)

    def test_duplicate_bundling_fails_closed(self):
        builder.bundle_webui_assets(self.root.parent)
        with self.assertRaisesRegex(RuntimeError, "missing_or_duplicated_sdd_static_reference"):
            builder.bundle_webui_assets(self.root.parent)

    def test_missing_overlay_fails_closed(self):
        (self.root / "sdd-ui.css").unlink()
        with self.assertRaisesRegex(RuntimeError, "missing_webui_bundle_source"):
            builder.bundle_webui_assets(self.root.parent)

    def test_non_iife_overlay_fails_closed(self):
        (self.root / "sdd-ui.js").write_bytes(b"alert(1);")
        with self.assertRaisesRegex(RuntimeError, "webui_iife_contract_changed"):
            builder.bundle_webui_assets(self.root.parent)

if __name__ == "__main__":
    unittest.main()
