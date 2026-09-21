# Landing page

The public landing page lives in `landing/` and is built to one self-contained
`index.html` by `landing/build.py`. `.github/workflows/gallery.yml` builds it together
with the theme gallery and publishes `index.html` to the root of the `gh-pages`
branch and the gallery to `themes/`, next to `source.json`, `icon.png` and
`screenshots/` (which `release.yml` publishes and this workflow never touches). It
looks like the gallery on purpose: same tokens, same frieze, same paper grain.

## Files

- `template.html`: the page. `{{token}}` placeholders and `<!--?key-->...<!--/?key-->`
  blocks that are removed when `key` is empty. An unknown token or key fails the build.
- `site.json`: facts and optional content. Edit this, not the HTML.
- `frieze.html`, `texture.txt`: fragments copied from the gallery so the two match.
  If the gallery's frieze or paper-grain background ever changes, copy the updated
  markup here too.
- `build.py`: validates `site.json` (https URLs only, required fields), reads the
  screenshot and icon URLs from `appstore/source.template.json`, renders the page.

Screenshots and the icon are never listed in `site.json`. They come from
`appstore/source.template.json`, so the page always shows exactly what the AltStore
source ships.

## Optional sections

Nothing is shown that `site.json` does not back. Leave a field empty (`""` or `[]`)
and the section, its nav link and its markup are absent from the output.

| Field | Shows when set |
|---|---|
| `min_ios`, `devices` | "Requires ..." in the hero note, and a supported-versions FAQ entry |
| `install_time` | "Allow about ..." under the Install heading |
| `install_step_images` | A screenshot row under the install steps (`src`, `alt`, optional `caption`) |
| `demo_video`, `demo_poster` | A "Watch it" section with a video, and a nav link |
| `testimonials` | A "Kind words" section (`quote`, `name`, optional `url`) |
| `community` | A "Find other readers" card (`name`, `url`) |
| `tip_url`, `tip_label` | A "Keep it going" card |
| `press_contact` | A press contact line in the footer |
| `changelog` | Entries in the "What is new" card (`version`, optional `date`, `notes`) |
| `og_image` | A large social preview image; otherwise the app icon is used |

The FAQ is `faq` in `site.json`. An entry with `"requires": "<key>"` is skipped
when that key is empty. Answers allow only `[label](https://url)` links.

## Things the page fills in itself

- The latest release (tag and date) in the "What is new" card is fetched in the
  browser from the GitHub releases API and shown only if the request succeeds.
- The mobile "Add to AltStore" bar appears once the hero buttons scroll away.
- Social preview tags (Open Graph, Twitter card) and schema.org
  `MobileApplication` JSON-LD are generated from `site.json` and the store JSON.
- Light/dark follows the system by default; `data-theme="light"`/`"dark"` on
  `<html>` overrides it, matching the gallery's own tokens.

## Rules for copy

Every claim on the page must come from the README, the docs, or the store JSON.
Do not add ratings, download counts or testimonials that are not real. The page
carries the same warning about unofficial AO3 apps as the README; keep it.
