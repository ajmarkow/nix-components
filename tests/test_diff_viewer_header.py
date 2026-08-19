import importlib.util
import re
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "diff-viewer-header.py"
CSS = Path(__file__).parents[1] / "skills" / "diff-viewer" / "frappe.css"
MODULE = Path(__file__).parents[1] / "modules" / "diff-viewer.nix"
PER_SYSTEM = Path(__file__).parents[1] / "per-system.nix"


class DiffViewerHeaderTest(unittest.TestCase):
    def test_hides_diff2html_generated_heading(self):
        self.assertIn("body > h1 {", CSS.read_text())

    def test_styles_file_list_header_and_expanded_list(self):
        css = CSS.read_text()
        self.assertIn(".d2h-file-list-header {", css)
        self.assertIn(".d2h-file-list {", css)
        self.assertIn(".d2h-file-list-line .d2h-file-name-wrapper {", css)

    def test_publishes_decorated_html_atomically(self):
        module = MODULE.read_text()
        self.assertIn('targetTmp="$outputDir/.$filename"', module)
        self.assertIn('mv "$targetTmp" "$target"', module)

    def test_flake_check_runs_diff_viewer_tests(self):
        self.assertIn("checks.diff-viewer", PER_SYSTEM.read_text())

    def test_adds_page_title_and_copyable_git_metadata(self):
        if not SCRIPT.exists():
            self.fail("diff-viewer header injector does not exist")

        spec = importlib.util.spec_from_file_location("diff_viewer_header", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with tempfile.TemporaryDirectory() as directory:
            html_path = Path(directory) / "diff.html"
            css_path = Path(directory) / "frappe.css"
            html_path.write_text(
                "<html><head><title>Old title</title></head>"
                '<body><div class="d2h-wrapper">Diff</div></body></html>'
            )
            css_path.write_text("body { color: white; }")

            module.decorate(
                html_path,
                css_path,
                repo="nix-components",
                branch="feature/header",
                commit="a1b2c3d",
            )
            result = html_path.read_text()

        self.assertIn("<title>nix-components / feature/header / a1b2c3d</title>", result)
        self.assertIn('<span class="dv-meta__label">Repo</span>', result)
        self.assertIn('<strong class="dv-meta__value">nix-components</strong>', result)
        self.assertIn('<span class="dv-meta__label">Branch</span>', result)
        self.assertIn('<strong class="dv-meta__value">feature/header</strong>', result)
        self.assertIn('data-commit="a1b2c3d"', result)
        self.assertIn('aria-label="Copy commit a1b2c3d"', result)
        self.assertIn('<code class="dv-meta__hash">a1b2c3d</code>', result)
        self.assertIn("navigator.clipboard.writeText", result)
        self.assertIn("body { color: white; }", result)
        self.assertLess(result.index('class="dv-page-header"'), result.index('class="d2h-wrapper"'))

    def test_escapes_metadata_with_regex_replacement_characters(self):
        spec = importlib.util.spec_from_file_location("diff_viewer_header", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with tempfile.TemporaryDirectory() as directory:
            html_path = Path(directory) / "diff.html"
            html_path.write_text("<html><head><title>Old</title></head><body></body></html>")

            try:
                module.decorate(
                    html_path,
                    None,
                    repo=r"nix\g<2>&<components>",
                    branch=r"feature\1&header",
                    commit="a1b2c3d",
                )
            except re.error as error:
                self.fail(f"metadata was parsed as a regex replacement: {error}")
            result = html_path.read_text()

        self.assertIn(r"nix\g&lt;2&gt;&amp;&lt;components&gt;", result)
        self.assertIn(r"feature\1&amp;header", result)


if __name__ == "__main__":
    unittest.main()
