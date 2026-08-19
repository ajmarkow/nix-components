#!/usr/bin/env python3
import argparse
import html
import re
from pathlib import Path


def decorate(html_path, css_path, repo, branch, commit):
    page = html_path.read_text()
    title = html.escape(f"{repo} / {branch} / {commit}")
    repo = html.escape(repo)
    branch = html.escape(branch)
    commit = html.escape(commit)

    header = f'''<header class="dv-page-header">
  <div class="dv-page-header__inner" aria-label="Diff details">
    <div class="dv-meta dv-meta--repo">
      <span class="dv-meta__label">Repo</span>
      <strong class="dv-meta__value">{repo}</strong>
    </div>
    <div class="dv-meta">
      <span class="dv-meta__label">Branch</span>
      <strong class="dv-meta__value">{branch}</strong>
    </div>
    <div class="dv-meta">
      <span class="dv-meta__label">Commit</span>
      <button class="dv-copy" type="button" data-commit="{commit}" aria-label="Copy commit {commit}" title="Copy commit {commit}">
        <code class="dv-meta__hash">{commit}</code>
        <span class="dv-copy__status" aria-live="polite">Copy</span>
      </button>
    </div>
  </div>
</header>'''

    script = '''<script>
document.querySelector(".dv-copy").addEventListener("click", async (event) => {
  const button = event.currentTarget;
  const status = button.querySelector(".dv-copy__status");
  try {
    await navigator.clipboard.writeText(button.dataset.commit);
    status.textContent = "Copied";
    button.classList.add("is-copied");
    window.setTimeout(() => {
      status.textContent = "Copy";
      button.classList.remove("is-copied");
    }, 1600);
  } catch {
    status.textContent = "Copy failed";
  }
});
</script>'''

    page = re.sub(
        r"<title>.*?</title>", lambda _: f"<title>{title}</title>", page, count=1, flags=re.S
    )
    if css_path and css_path.is_file():
        page = page.replace("</head>", f"<style>{css_path.read_text()}</style></head>", 1)
    page = re.sub(r"(<body[^>]*>)", lambda match: match.group(1) + header, page, count=1)
    page = page.replace("</body>", f"{script}</body>", 1)
    html_path.write_text(page)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("html", type=Path)
    parser.add_argument("--css", type=Path)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    decorate(args.html, args.css, args.repo, args.branch, args.commit)


if __name__ == "__main__":
    main()
