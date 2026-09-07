# Aphotic Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Jekyll-powered GitHub Pages site that renders the public Aphotic Wiki as native documentation.

**Architecture:** Templates and assets live in `site/`. A Python standard-library preparation script converts a shallow public Wiki clone into Jekyll collection pages with stable routes and rewritten links. A Pages workflow builds only `site/` and deploys its artifact.

**Tech Stack:** Jekyll, Liquid, GitHub Pages Actions, HTML, CSS, vanilla JavaScript, Python standard library.

**Spec:** `site/SITE-DESIGN.md`

## Global Constraints

- Do not read, change, import, or publish the repository's private `docs/` directory.
- Public Wiki Markdown remains the documentation authority.
- Use no frontend framework, database, runtime API, remote font, or generated imagery.
- Use existing Aphotic marks and legitimate project screenshots only.
- Every URL must work with `baseurl: /aphotic-hypr` and a future root-domain deployment.
- The desktop application, installer, profiles, themes, and existing workflows stay unchanged.

---

### Task 1: Test the site contract

**Files:** Create `site/tests/test_site.py` and `site/tests/fixtures/Example-Page.md`.

**Interfaces:** Tests consume the converter, Jekyll config, pages, layouts, assets, and workflow. They run with `python3 -m unittest discover -s site/tests -v`.

- [ ] Write failing tests that require Wiki front matter, `/docs/<slug>/` link rewriting, and `baseurl: /aphotic-hypr`.
- [ ] Run the tests and confirm they fail because the converter and Jekyll files are missing.
- [ ] Commit with `site: add pages contract tests`.

### Task 2: Prepare the Wiki and configure Jekyll

**Files:** Create `site/scripts/prepare_wiki.py`, `site/_config.yml`, `site/Gemfile`, and `site/.gitignore`.

**Interfaces:** `prepare_wiki.py --wiki <clone> --output site/_docs` creates collection documents with `layout: docs`, title, slug, source URL, and rewritten relative links. `_config.yml` sets the `docs` collection output to `/docs/:name/`.

- [ ] Implement the minimal converter, configuration, exclusions, and Pages base path.
- [ ] Run the contract tests and confirm the collection conversion is green.
- [ ] Commit with `site: prepare public wiki for jekyll`.

### Task 3: Create the Aphotic visual system

**Files:** Create `site/_layouts/default.html`, `site/_layouts/docs.html`, `site/_includes/header.html`, `site/_includes/footer.html`, `site/_includes/document-nav.html`, `site/assets/css/site.css`, `site/assets/js/site.js`, and selected SVG marks under `site/assets/icons/`.

**Interfaces:** Layouts consume Jekyll front matter and `relative_url`. They produce a semantic shell, responsive navigation, accent picker, code-copy controls, and controlled documentation measure.

- [ ] Add failing tests for a skip link, main landmark, visible focus rules, reduced-motion rules, and persisted accent selection.
- [ ] Implement the abyssal token system, layout, mobile disclosure navigation, section index, and small JavaScript enhancements.
- [ ] Run tests and commit with `site: add aphotic documentation theme`.

### Task 4: Add primary pages and metadata

**Files:** Create `site/index.md`, `site/documentation.md`, `site/plugins.md`, `site/gallery.md`, `site/roadmap.md`, `site/robots.txt`, `site/sitemap.xml`, and selected existing screenshots under `site/assets/gallery/`.

**Interfaces:** Pages consume current public Wiki facts and selected existing project images. They produce minimal routes with metadata and no unsupported claims.

- [ ] Add failing content tests for relative URLs, per-page metadata, site-local gallery assets, and absence of private-doc paths.
- [ ] Implement the five public pages, copy selected project assets, then run the full test suite.
- [ ] Commit with `site: add public pages and gallery`.

### Task 5: Build and deploy with GitHub Pages

**Files:** Create `.github/workflows/deploy-pages.yml`; modify `site/tests/test_site.py`.

**Interfaces:** The workflow clones the public Wiki, runs the converter, builds `site/` with `actions/jekyll-build-pages@v1`, uploads the generated artifact, and deploys it through `actions/deploy-pages@v4` after pushes to `main`.

- [ ] Add a failing workflow contract test for the clone, preparation, build, artifact, and deploy steps.
- [ ] Implement the official Pages workflow with minimal permissions and a non-cancelling deployment concurrency group.
- [ ] Run static tests, generate a collection from a fresh Wiki clone, inspect the diff with `git diff origin/main...HEAD --check`, and commit with `site: deploy wiki docs to pages`.
