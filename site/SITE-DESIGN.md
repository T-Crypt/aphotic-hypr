# Aphotic Pages Design

## Goal

Publish a lightweight, static public website for Aphotic-Hypr. It presents
the project as a modular, resource-aware Linux desktop platform and renders
the public GitHub Wiki as the documentation source of truth.

## Boundaries

- The existing repository `docs/` directory remains private, gitignored, and
  untouched.
- Only public Wiki Markdown is imported into the documentation build.
- The application, installer, profiles, themes, and existing CI remain
  unchanged except for an additive Pages workflow.
- The website uses Jekyll, HTML, CSS, and small vanilla JavaScript helpers.
  It has no client-side framework or data service.

## Source and build flow

The site source lives under `site/`. A deployment workflow checks out the
repository and a shallow copy of the public Wiki, stages the Wiki Markdown
under the Jekyll source, then builds a static artifact with Jekyll.

The build applies the following transformations:

1. Wiki page names become stable `/docs/<slug>/` routes.
2. Relative Wiki links become site-internal documentation links.
3. GitHub-flavored alerts become semantic note, warning, and important
   callouts.
4. Markdown headings receive stable IDs and appear in the page section index.
5. The generated documentation exposes its public Wiki source link.

The generated artifact alone is deployed to GitHub Pages. The Wiki clone and
build staging directory are never committed or published as source files.

## Site structure

```text
site/
├── _config.yml                 Jekyll configuration and project-Pages base URL
├── _layouts/                   Shared document and marketing page layouts
├── _includes/                  Header, footer, section index, and metadata
├── assets/
│   ├── css/site.css            Design tokens, layout, documentation, responsive rules
│   ├── js/site.js              Accent selection, menu state, code-copy controls
│   ├── icons/                  Existing Aphotic marks and favicon
│   └── gallery/                Selected existing project screenshots only
├── docs/
│   └── index.md                Documentation landing and generated Wiki pages
├── index.md                    Restrained project introduction
├── plugins.md                  Current public plugin roster from the Wiki
├── gallery.md                  Selected, legitimate project screenshots
├── roadmap.md                  Shipped, experimental, and planned public status
├── robots.txt
├── sitemap.xml
└── SITE-DESIGN.md              This design record; excluded from generated output
```

## Visual system

The default theme is an abyssal near-black field with soft off-white text,
cool gray metadata, charcoal rules, and a restrained cyan-blue accent. CSS
custom properties define every color, spacing scale, type scale, and border
treatment.

Four compact accent presets change only the variable set. The chosen preset
is stored in `localStorage`; no network call, image generation, or continuous
animation is involved. A faint depth-line texture is static and low contrast.

Navigation and metadata use system monospace fonts. Long-form body text uses
the system sans-serif stack. Desktop pages have generous whitespace and a
controlled reading measure. Mobile pages collapse navigation into a keyboard
accessible disclosure without hiding document structure.

## Pages

- Home: project statement, verified installation entry point, and concise
  links to the major shipped areas.
- Documentation: the complete public Wiki rendered as native, linked HTML.
- Plugins: the current public roster, status/category/capability facts, and
  real installation command.
- Gallery: a limited selection of existing repository screenshots with useful
  captions. No fabricated screenshots or generated illustrations.
- Roadmap: current status drawn only from public release notes, project
  status, and linked GitHub issues. Planned work is labeled as planned.

## Documentation experience

Each documentation page has semantic headings, a contextual document list,
an on-page section index, anchor links, previous/next links, tables, keyboard
readable code blocks, and visible callouts. Code blocks offer a compact copy
button with a non-JavaScript readable fallback. The content area remains
readable on wide displays and scrolls code horizontally instead of wrapping
commands incorrectly.

## Accessibility and metadata

The theme meets contrast requirements for primary text and focus states. The
site uses landmarks, one `h1` per page, ordered heading levels, descriptive
image alt text, reduced-motion rules, keyboard-operable controls, and a skip
link. Every page receives title, description, canonical, Open Graph, and
favicon metadata. `robots.txt` and `sitemap.xml` use the configured base URL
so repository Pages deployments work before a custom domain exists.

## Verification

- Build the site with the same Jekyll command used by the workflow.
- Check every generated local link, anchor target, image source, and sitemap
  URL under the repository Pages base path.
- Exercise accent persistence and each code-copy control in a browser.
- Check responsive desktop and mobile widths, keyboard focus order, and
  reduced-motion behavior.
- Confirm no path from the private `docs/` directory is in the generated
  artifact or workflow input.
