import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SiteContractTests(unittest.TestCase):
    def test_wiki_page_becomes_a_docs_collection_page(self):
        script = ROOT / "scripts" / "prepare_wiki.py"
        self.assertTrue(script.exists())

    def test_site_keeps_repository_pages_baseurl(self):
        self.assertIn('baseurl: "/aphotic-hypr"', (ROOT / "_config.yml").read_text())

    def test_primary_pages_exist(self):
        for name in ("index.md", "documentation.md", "plugins.md", "gallery.md", "roadmap.md"):
            self.assertTrue((ROOT / name).exists(), name)

    def test_internal_design_files_are_not_public_site_sources(self):
        private_names = ("SITE-DESIGN.md", "SITE-IMPLEMENTATION-PLAN.md")
        for name in private_names:
            self.assertFalse((ROOT / name).exists(), name)
            self.assertIn(name, (ROOT / ".gitignore").read_text())

    def test_home_links_use_docs_collection_routes(self):
        home = (ROOT / "index.md").read_text()
        self.assertNotIn("/documentation/getting-started/", home)
        self.assertIn("/docs/getting-started/", home)

    def test_copy_control_copies_code_only(self):
        script = (ROOT / "assets" / "js" / "site.js").read_text()
        self.assertIn("querySelector('code')", script)

    def test_robots_is_processed_by_jekyll(self):
        self.assertTrue((ROOT / "robots.txt").read_text().startswith("---"))

    def test_accessibility_and_theme_hooks_exist(self):
        layout = (ROOT / "_layouts" / "default.html").read_text()
        css = (ROOT / "assets" / "css" / "site.css").read_text()
        script = (ROOT / "assets" / "js" / "site.js").read_text()
        self.assertIn('skip-link', layout)
        self.assertIn('id="content"', layout)
        self.assertIn(':focus-visible', css)
        self.assertIn('prefers-reduced-motion', css)
        self.assertIn('localStorage', script)

    def test_pages_workflow_exists(self):
        workflow = (ROOT.parent / ".github" / "workflows" / "deploy-pages.yml").read_text()
        for needle in ('github.repository }}.wiki.git', 'prepare_wiki.py', 'jekyll-build-pages', 'deploy-pages'):
            self.assertIn(needle, workflow)
        self.assertIn("if: github.event_name != 'pull_request'", workflow)


if __name__ == "__main__":
    unittest.main()
