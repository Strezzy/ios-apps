# SPDX-License-Identifier: GPL-3.0-or-later
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from scripts.update_catalog import update, readme_text


class CatalogTests(unittest.TestCase):
    def test_other_app_refresh_retains_glint_and_all_existing_apps(self):
        catalog = json.loads((ROOT / 'apps.json').read_text())
        registry = json.loads((ROOT / 'app-registry.json').read_text())
        before = {a['bundleIdentifier'] for a in catalog['apps']}
        self.assertIn('com.strezzy.glint', before)
        result = update(copy.deepcopy(catalog), registry, [], 'unrelated-release', '2026-01-01', '')
        self.assertEqual({a['bundleIdentifier'] for a in result['apps']}, before)
        glint = next(a for a in result['apps'] if a['bundleIdentifier'] == 'com.strezzy.glint')
        self.assertEqual(glint['versions'], next(a for a in catalog['apps'] if a['bundleIdentifier'] == 'com.strezzy.glint')['versions'])
        readme = readme_text(result, (ROOT / 'scripts/README.template.md').read_text())
        self.assertIn('**Glint**', readme)
        self.assertIn(glint['versions'][0]['downloadURL'], readme)


if __name__ == '__main__':
    unittest.main(verbosity=2)
