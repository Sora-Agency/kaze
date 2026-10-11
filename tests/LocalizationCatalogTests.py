import json
import pathlib
import plistlib
import re
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def catalog(language):
    path = ROOT / "src/Localization" / f"{language}.lproj/Localizable.strings"
    return json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))


class CatalogTests(unittest.TestCase):
    def test_languages_have_same_keys_and_interpolation(self):
        english, spanish = catalog("en"), catalog("es")
        self.assertEqual(english.keys(), spanish.keys())
        self.assertGreater(len(english), 300)
        for key, text in english.items():
            with self.subTest(key=key):
                self.assertTrue(text.strip())
                placeholders = r"%(?!%)(?:\d+\$)?[.\d]*[@dfld]+"
                self.assertEqual(re.findall(placeholders, text), re.findall(placeholders, spanish[key]))

    def test_plural_catalogs_match(self):
        catalogs = [plistlib.loads((ROOT / "src/Localization" / f"{language}.lproj/Localizable.stringsdict").read_bytes()) for language in ("en", "es")]
        self.assertEqual(catalogs[0].keys(), catalogs[1].keys())
        for key in catalogs[0]:
            for data in catalogs:
                self.assertEqual(data[key]["count"]["NSStringFormatValueTypeKey"], "ld")
                for category in ("one", "other"):
                    self.assertIn("%ld", data[key]["count"][category])
            for category in ("one", "other"):
                self.assertEqual(catalogs[0][key]["count"][category].count("%@"), catalogs[1][key]["count"][category].count("%@"))

    def test_localized_bundle_metadata(self):
        info = plistlib.loads((ROOT / "src/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleLocalizations"], ["en", "es"])
        self.assertEqual(info["CFBundleDevelopmentRegion"], "en")

    def test_bilingual_documentation_links(self):
        for name in ("README.md", "README.es.md", "CONTRIBUTING.md", "CONTRIBUTING.es.md", "docs/PUBLISHING.md", "docs/PUBLISHING.es.md"):
            path = ROOT / name
            for target in re.findall(r"\]\(([^)]+)\)", path.read_text()):
                if not target.startswith(("https:", "#")):
                    self.assertTrue((path.parent / target.split("#")[0]).exists(), f"{name}: {target}")


if __name__ == "__main__":
    unittest.main()
