# Full-screen top clearance audit

In full-screen reading `WebViewController.hideBars()` hides the bars and cancels the top safe
area inset, so the page starts at the top edge of the screen and `notchCoverView` paints the
theme's page color over the top inset (about 62pt on current Dynamic Island iPhones; 59pt on
earlier ones). Anything the theme draws above that line is hidden. The rule for every theme is
in `nnwtheme-format.md`, "Full-screen reading: space above the title" (68px above the title).

## Running the check

```
pip install playwright && playwright install chromium
python3 buildscripts/theme-audit/check_fullscreen_top.py                      # Themes/ and gallery-themes/
python3 buildscripts/theme-audit/check_fullscreen_top.py "Themes/Nectar.nnwtheme" --markdown out.md --json out.json
```

It renders each bundle's template and stylesheet (with `core.css`) at 393px wide in light and
dark, with and without a feed name and with a short and a long title, and measures the top of
the first title line and the top of the first painted content. Exit status 1 means a theme
FAILs. Fonts are not loaded (the `@import` is dropped), so line counts are approximate; the
distance from the top is mostly layout. It is not part of CI. Bundles in
`buildscripts/theme-audit/intentional-bleed.txt` are reported as BLEED rather than HEAD-CUT or
ORNAMENT-CUT when their design deliberately starts under the cover.

| Status | Meaning |
|---|---|
| FAIL | No title element, the title starts above 68px, or it is not hit-testable |
| HEAD-CUT | The title clears 68px, but a running head (feed link, date, byline before the title) starts above 62px, so it is partly or wholly under the cover |
| ORNAMENT-CUT | No running head, but other painted content starts above 62px |
| BLEED | As HEAD-CUT or ORNAMENT-CUT, but listed as intentional |
| OK | Everything painted starts at or below 62px |

## Results (199 bundles: 10 in `Themes/`, 187 in `gallery-themes/`, 2 candidates not installed)

40 OK, 151 HEAD-CUT, 3 ORNAMENT-CUT, 5 FAIL. Measured in headless Chromium with the iOS branch of
the stylesheet, not on a device. The first pass of this audit measured the macOS branch, which adds
about 20px of body padding the app never has, and overstated the clearance; the numbers here are
the corrected ones.

- **Titles that were cut off:** 37 bundles started the title above 68px. Thirty-two were fixed by
  appending `html { padding-top }` so the title starts at about 76px (the rule is commented in each
  stylesheet), and each got a `Version` bump. That includes the bundled Midnight Blue and
  Duskbloom. Nectar was fixed differently: its vine band sat at 18px, so `.t` top padding is now
  66px and the whole band starts below the cover. **Run `scripts/regenerate-theme-colors.sh` and
  commit the JSON**, because three bundled stylesheets changed (Nectar, Midnight Blue, Duskbloom)
  and their table keys moved. The generated bundles also get the rule by hand: re-running
  `generate_ported_themes.py` would remove it (noted in that file).
- **Still FAIL (5): Appanoose 53px, Biblioteca 38, NewsFax 25, Sepia 55, Tiqoe Dark 55.** All are
  pinned to upstream NetNewsWire by hash (`gallery/upstream-compatible.txt`,
  `gallery/test_upstream_pins.py`), so changing them is a decision, not a fix to slip in.
  Promenade is pinned too and is ORNAMENT-CUT. Craft Table and Mid-century Jost keep a decorative
  element at about 40px that `html` padding does not move; their titles clear 76px.
- **Running heads:** 155 bundles have one (feed link, date, byline before the title). In 90 it is
  partly under the cover and in 65 entirely under it. In 148 the head is also what puts the title
  below 68px: hide it and the title starts above 68px. So the head works as a spacer and in practice
  it is cut off or hidden.
- **Watch Later** measures OK: its thumbnail block starts at 68px, below the cover. It is in
  `intentional-bleed.txt`, which currently changes nothing; add a name there when a design should
  start under the cover on purpose.

## Deciding which themes keep a running head

The measurements say no theme needs the head for its function: it holds a feed name that the
app hides by default (`showFeedNameInReaderView` is off, so `removeFeedNameLink()` removes the
link), a date, and a byline that is often empty. What it does do is supply the 68px.

1. **Fix it once in the app (recommended).** Change `updateTopSafeAreaForFullScreen()` to leave
   the notch inset in place instead of cancelling it. The page then starts below the cover at
   scroll position 0 and scrolls up under the cover as usual, so no reading area is lost, and
   every theme (including imported ones) clears the cover with no per-theme padding. Not
   implemented: it changes full-screen behavior everywhere and has to be checked on a device.
2. **Edit the themes.** Keep a head only where it is part of the design (capsules, bands,
   stamps) and move it to start at 62px or lower; for all other themes drop the head markup and
   put 68px of `padding-top` on the wrapper. About 150 bundles, each with a `Version` bump.

The 29 new bundles below take option 2's shape from the start: no running head, 76px above the
first painted element.

## Bundles generated from clean-room-theme-specs.md

`buildscripts/theme-generation/generate_spec_themes.py` writes 29 original bundles to
`gallery-themes/` from the design tables in `spec_themes_a.py`, `spec_themes_b.py` and
`spec_themes_c.py` (shared helpers in `spec_common.py`). Each is a reading layout for an article,
not a Tumblr blog page: the source themes were read for technique and palette, the names, copy and
shapes are new, and every `License.md` carries an "Inspired by" credit. Licenses are left as "not
yet decided; set one before publishing", and the four themes by palemomos also record that its
terms forbid recreating the theme, so those four share only general techniques.

All 29 pass this audit (the lowest title is Strip Credits at 73px),
build in `gallery/build.py`, and have ink contrast of at least 7:1 and link contrast of at least
4.5:1 against the page color in light and dark. Font families (Google Fonts) were chosen from
memory and were not checked online. Companion pages and collapsibles in the spec (P1 to P4, C) were
not built, since they are not article themes.

## Full table

| Theme | Where | Status | Title top | Content top | Title w/o head | Head | Note |
|---|---|---|---|---|---|---|---|
| Dark Academia | Themes | HEAD-CUT | 127.9 | 41.9 | 49.9 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Duskbloom | Themes | HEAD-CUT | 76.8 | 32.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 33px, under the 62px cover |
| High Contrast | Themes | OK | 71 | 71 | 71 | none |  |
| Midnight Blue | Themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Nectar | Themes | OK | 153 | 66 | 153 | none |  |
| Night Amber | Themes | HEAD-CUT | 84 | 40.9 | 6 | partly hidden, needed for clearance | painted content starts at 41px, under the 62px cover |
| OLED Black | Themes | HEAD-CUT | 87 | 41.9 | 9 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Reversi | Themes | OK | 71 | 71 | 71 | none |  |
| Solarized | Themes | HEAD-CUT | 113 | 41.9 | 35 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| System | Themes | HEAD-CUT | 88.1 | 12.5 | 20.1 | partly hidden, needed for clearance | painted content starts at 12px, under the 62px cover |
| 1-Bit Desktop | gallery-themes | HEAD-CUT | 95 | 41.9 | 17 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Airport Paperback | gallery-themes | HEAD-CUT | 92 | 30.0 | 24 | hidden, needed for clearance | painted content starts at 30px, under the 62px cover |
| Aldine | gallery-themes | HEAD-CUT | 128.8 | 3 | 37 | hidden, needed for clearance | painted content starts at 3px, under the 62px cover |
| Appanoose | gallery-themes | FAIL | 53.4 | 3 | 19 | hidden, needed for clearance | title starts at 53px |
| Arcade CGA | gallery-themes | HEAD-CUT | 81 | 30.0 | 13 | hidden, needed for clearance | painted content starts at 30px, under the 62px cover |
| Architect's Drafting Sheet | gallery-themes | HEAD-CUT | 88 | 41.9 | 10 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Art Deco | gallery-themes | HEAD-CUT | 142 | 41.9 | 64 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Art Nouveau | gallery-themes | HEAD-CUT | 118 | 31.0 | 50 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Arts & Crafts | gallery-themes | HEAD-CUT | 122.6 | 41.9 | 44.6 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Atomic Age Populuxe | gallery-themes | HEAD-CUT | 87 | 41.9 | 9 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Aurora Glow | gallery-themes | HEAD-CUT | 96 | 31.0 | 28 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Azulejo | gallery-themes | HEAD-CUT | 114 | 41.9 | 36 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Bauhaus | gallery-themes | HEAD-CUT | 80 | 31.0 | 12 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Beacon | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 41 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Beetlejuice | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Beige Box | gallery-themes | HEAD-CUT | 85 | 31.0 | 17 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Bento Grid | gallery-themes | HEAD-CUT | 109 | 41.9 | 31 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Biblioteca | gallery-themes | FAIL | 38 | 15 | 14 | hidden, needed for clearance | title starts at 38px |
| Birdsite | gallery-themes | HEAD-CUT | 179 | 31.0 | 111 | hidden, optional | painted content starts at 31px, under the 62px cover |
| Black & White | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Bridge Command | gallery-themes | HEAD-CUT | 82 | 31.0 | 14 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Broadsheet | gallery-themes | OK | 76 | 76 | 76 | none |  |
| Bullet Journal | gallery-themes | HEAD-CUT | 99 | 41.9 | 21 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Cassette Futurism | gallery-themes | HEAD-CUT | 97 | 41.9 | 19 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Catalogue Bevel | gallery-themes | OK | 91 | 76 | 91 | none |  |
| Catppuccin | gallery-themes | HEAD-CUT | 103 | 41.9 | 25 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Charcoal Rose | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Commodore 64 | gallery-themes | HEAD-CUT | 114 | 41.9 | 36 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Constellations | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Constructivist | gallery-themes | HEAD-CUT | 87 | 31.0 | 19 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Cottagecore | gallery-themes | HEAD-CUT | 115 | 41.9 | 37 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Craft Chalkboard Badge | gallery-themes | HEAD-CUT | 93 | 30.0 | 25 | hidden, needed for clearance | painted content starts at 30px, under the 62px cover |
| Craft Table | gallery-themes | ORNAMENT-CUT | 76.3 | 42 | 76.3 | none | painted content starts at 42px, under the 62px cover |
| Crimson Gothic | gallery-themes | HEAD-CUT | 117 | 41.9 | 39 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Curtain Call | gallery-themes | HEAD-CUT | 97 | 31.0 | 29 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Cyanotype | gallery-themes | HEAD-CUT | 105 | 41.9 | 27 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Deco Line | gallery-themes | HEAD-CUT | 127.8 | 3 | 36 | hidden, needed for clearance | painted content starts at 3px, under the 62px cover |
| Deconstructed Zine | gallery-themes | HEAD-CUT | 76.3 | 45.0 | 8.3 | partly hidden, needed for clearance | painted content starts at 45px, under the 62px cover |
| Delft Blue | gallery-themes | HEAD-CUT | 115 | 41.9 | 37 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Denim and Rivets | gallery-themes | HEAD-CUT | 127 | 41.9 | 49 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Didone Editorial | gallery-themes | OK | 76.2 | 76.2 | 76.2 | none |  |
| Disco | gallery-themes | HEAD-CUT | 92 | 31.0 | 24 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Dracula | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Draft Sheet | gallery-themes | OK | 119 | 119 | 119 | none |  |
| Duotone Gradient | gallery-themes | HEAD-CUT | 100 | 31.0 | 32 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Dusk Cards | gallery-themes | OK | 105 | 105 | 105 | none |  |
| Dusky Purple | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Dyslexia-Friendly | gallery-themes | HEAD-CUT | 90 | 41.9 | 12 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| E-Ink | gallery-themes | HEAD-CUT | 87 | 41.9 | 9 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Ember | gallery-themes | HEAD-CUT | 76.8 | 16.9 | 30.1 | hidden, needed for clearance | painted content starts at 17px, under the 62px cover |
| Evangeltron | gallery-themes | HEAD-CUT | 105 | 30.0 | 37 | hidden, needed for clearance | painted content starts at 30px, under the 62px cover |
| Evil Magazine | gallery-themes | HEAD-CUT | 84 | 31.0 | 16 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Fansub | gallery-themes | HEAD-CUT | 94 | 31.0 | 26 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Film Noir | gallery-themes | HEAD-CUT | 93 | 30.0 | 25 | hidden, needed for clearance | painted content starts at 30px, under the 62px cover |
| Flat Long-Shadow | gallery-themes | HEAD-CUT | 92 | 31.0 | 24 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Four Nations | gallery-themes | OK | 76 | 77 | 76 | none |  |
| Four Panel | gallery-themes | OK | 90.2 | 76 | 90.2 | none |  |
| Frosted Wallpaper | gallery-themes | OK | 94 | 76 | 94 | none |  |
| Frostline | gallery-themes | OK | 75 | 75 | 75 | none |  |
| Frutiger Aero | gallery-themes | HEAD-CUT | 94 | 31.0 | 26 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Futurism | gallery-themes | HEAD-CUT | 101 | 41.9 | 23 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Galactic Matinee | gallery-themes | HEAD-CUT | 209 | 31.0 | 141 | hidden, optional | painted content starts at 31px, under the 62px cover |
| Game Boy Green | gallery-themes | HEAD-CUT | 101 | 41.9 | 23 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Giallo | gallery-themes | HEAD-CUT | 101 | 41.9 | 23 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Glasgow Style | gallery-themes | HEAD-CUT | 107 | 31.0 | 39 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Googie | gallery-themes | HEAD-CUT | 76 | 31.0 | 8 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Gradient Stage | gallery-themes | OK | 94 | 76 | 94 | none |  |
| Graph Desk | gallery-themes | OK | 102.6 | 83.1 | 102.6 | none |  |
| Green Phosphor | gallery-themes | HEAD-CUT | 84 | 41.9 | 6 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Grimoire | gallery-themes | HEAD-CUT | 93 | 41.9 | 15 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Gruvbox | gallery-themes | HEAD-CUT | 99 | 41.9 | 21 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Hand of Cards | gallery-themes | OK | 97.2 | 73.6 | 97.2 | none |  |
| Heist Night | gallery-themes | HEAD-CUT | 135.1 | 40 | 48.4 | partly hidden, needed for clearance | painted content starts at 40px, under the 62px cover |
| Hung Dates | gallery-themes | OK | 75 | 75 | 75 | none |  |
| Hyperlegible | gallery-themes | HEAD-CUT | 89.2 | 3 | 21.2 | partly hidden, needed for clearance | painted content starts at 3px, under the 62px cover |
| Illuminated Codex | gallery-themes | OK | 76.3 | 76.3 | 76.3 | none |  |
| Illuminated Manuscript | gallery-themes | HEAD-CUT | 87 | 41.9 | 9 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Impact Frame | gallery-themes | HEAD-CUT | 92 | 31.0 | 24 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Ink and Mist | gallery-themes | HEAD-CUT | 131 | 31.0 | 63 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Isotype | gallery-themes | HEAD-CUT | 76 | 31.0 | 8 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Kelmscott | gallery-themes | HEAD-CUT | 125.6 | 3 | 73.4 | hidden, optional | painted content starts at 3px, under the 62px cover |
| Kennerley | gallery-themes | HEAD-CUT | 108.1 | 3 | 36 | hidden, needed for clearance | painted content starts at 3px, under the 62px cover |
| Large Print | gallery-themes | HEAD-CUT | 87 | 41.9 | 9 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Late Night Lounge | gallery-themes | OK | 90 | 76 | 90 | none |  |
| Leaning Tape | gallery-themes | OK | 104.1 | 104.1 | 104.1 | none |  |
| Leather-Bound | gallery-themes | HEAD-CUT | 118 | 41.9 | 40 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Letterpress Broadside | gallery-themes | HEAD-CUT | 107 | 41.9 | 29 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Library Card Catalog | gallery-themes | HEAD-CUT | 89 | 41.9 | 11 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Lilac Card | gallery-themes | OK | 150 | 106 | 150 | none |  |
| Linocut | gallery-themes | HEAD-CUT | 102 | 41.9 | 24 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Lotería | gallery-themes | HEAD-CUT | 138 | 41.9 | 60 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Main Street Weekly | gallery-themes | HEAD-CUT | 75 | 31.0 | 7 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Marble and Gold | gallery-themes | HEAD-CUT | 115 | 41.9 | 37 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Marigold Press | gallery-themes | HEAD-CUT | 124.7 | 3 | 35 | hidden, needed for clearance | painted content starts at 3px, under the 62px cover |
| Marker Sweep | gallery-themes | OK | 97 | 97 | 97 | none |  |
| Matisse Paper Cutouts | gallery-themes | HEAD-CUT | 81 | 30.0 | 13 | hidden, needed for clearance | painted content starts at 30px, under the 62px cover |
| Memphis | gallery-themes | HEAD-CUT | 97 | 31.0 | 29 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Mid-Century Modern | gallery-themes | HEAD-CUT | 86 | 41.9 | 8 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Mid-century Jost | gallery-themes | ORNAMENT-CUT | 76.2 | 37 | 76.2 | none | painted content starts at 37px, under the 62px cover |
| Midnight Teal | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Moonlit Wisteria | gallery-themes | HEAD-CUT | 76.8 | 32.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 33px, under the 62px cover |
| Moonshot | gallery-themes | HEAD-CUT | 86 | 31.0 | 18 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Museum Placard | gallery-themes | HEAD-CUT | 115 | 41.9 | 37 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Mystery | gallery-themes | HEAD-CUT | 76.4 | 29.9 | 41.6 | partly hidden, needed for clearance | painted content starts at 30px, under the 62px cover |
| Neo-Brutalist | gallery-themes | HEAD-CUT | 93 | 31.0 | 25 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Neon Silhouette | gallery-themes | HEAD-CUT | 90 | 31.0 | 22 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| New Wave | gallery-themes | HEAD-CUT | 72 | 31.0 | 4 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| NewsFax | gallery-themes | FAIL | 25 | 6 | 25 | none | title starts at 25px |
| Nord | gallery-themes | HEAD-CUT | 107 | 41.9 | 29 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Nordic Folk | gallery-themes | HEAD-CUT | 111 | 40.9 | 33 | partly hidden, needed for clearance | painted content starts at 41px, under the 62px cover |
| Numeral Window | gallery-themes | OK | 89 | 89 | 89 | none |  |
| Observatory Log | gallery-themes | OK | 92 | 76 | 92 | none |  |
| Op Art | gallery-themes | HEAD-CUT | 88 | 31.0 | 20 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Opening Credits | gallery-themes | HEAD-CUT | 99 | 31.0 | 31 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Papel Picado | gallery-themes | HEAD-CUT | 145 | 41.9 | 67 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Papercut Layers | gallery-themes | HEAD-CUT | 140 | 41.9 | 62 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Park Service Brochure | gallery-themes | HEAD-CUT | 100 | 41.9 | 22 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Pastel Whimsy | gallery-themes | HEAD-CUT | 76.8 | 31.9 | 41.1 | partly hidden, needed for clearance | painted content starts at 32px, under the 62px cover |
| Patent Drawing | gallery-themes | HEAD-CUT | 107 | 41.9 | 29 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Pen Margins | gallery-themes | OK | 92 | 76 | 92 | none |  |
| Penny Gazette | gallery-themes | OK | 101.2 | 76 | 101.2 | none |  |
| Perseus | gallery-themes | HEAD-CUT | 76.7 | 17.9 | 41.9 | partly hidden, needed for clearance | painted content starts at 18px, under the 62px cover |
| Persian Miniature | gallery-themes | HEAD-CUT | 126 | 41.9 | 48 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Pinerose | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Pinned Tags | gallery-themes | OK | 89 | 89 | 89 | none |  |
| Pixel Notebook | gallery-themes | OK | 91 | 76 | 91 | none |  |
| Podium | gallery-themes | HEAD-CUT | 160 | 31.0 | 92 | hidden, optional | painted content starts at 31px, under the 62px cover |
| Polish Poster School | gallery-themes | HEAD-CUT | 105.5 | 41.9 | 27.5 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Posterized Stencil | gallery-themes | HEAD-CUT | 190 | 31.0 | 122 | hidden, optional | painted content starts at 31px, under the 62px cover |
| Poudre et Plume | gallery-themes | HEAD-CUT | 76.8 | 29.9 | 41.1 | partly hidden, needed for clearance | painted content starts at 30px, under the 62px cover |
| Powder Pink | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Promenade | gallery-themes | ORNAMENT-CUT | 85 | 3 | 85 | none | painted content starts at 3px, under the 62px cover |
| Psychedelic | gallery-themes | HEAD-CUT | 95 | 31.0 | 27 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Pulp Magazine | gallery-themes | HEAD-CUT | 77 | 31.0 | 9 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Quilt Block | gallery-themes | HEAD-CUT | 123 | 40.9 | 45 | partly hidden, needed for clearance | painted content starts at 41px, under the 62px cover |
| Ribbon Spread | gallery-themes | OK | 97 | 97 | 97 | none |  |
| Risograph | gallery-themes | HEAD-CUT | 96 | 41.9 | 18 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Rosarivo | gallery-themes | HEAD-CUT | 127.9 | 3 | 36 | hidden, needed for clearance | painted content starts at 3px, under the 62px cover |
| Rosé Pine Dawn | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Rosé Pine Moon | gallery-themes | HEAD-CUT | 76.8 | 30.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Rosé Pine | gallery-themes | HEAD-CUT | 76.8 | 16.9 | 30.1 | hidden, needed for clearance | painted content starts at 17px, under the 62px cover |
| Runway | gallery-themes | HEAD-CUT | 74 | 31.0 | 6 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Sachplakat | gallery-themes | HEAD-CUT | 90 | 31.0 | 22 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Screenplay | gallery-themes | OK | 76.6 | 76.6 | 76.6 | none |  |
| Secession | gallery-themes | HEAD-CUT | 114 | 30.0 | 46 | hidden, needed for clearance | painted content starts at 30px, under the 62px cover |
| Sepia Paper | gallery-themes | HEAD-CUT | 93 | 41.9 | 15 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Sepia | gallery-themes | FAIL | 54.8 | 7.9 | 20.1 | hidden, needed for clearance | title starts at 55px |
| Ship's Log | gallery-themes | HEAD-CUT | 92 | 41.9 | 14 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Showa Retro | gallery-themes | HEAD-CUT | 105 | 41.9 | 27 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Silent Film Intertitle | gallery-themes | HEAD-CUT | 123 | 41.9 | 45 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Skate Zine | gallery-themes | HEAD-CUT | 106 | 31.0 | 38 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Sky Dialogue | gallery-themes | OK | 95 | 76 | 95 | none |  |
| Square Wall | gallery-themes | OK | 92 | 76 | 92 | none |  |
| Sticker Pop | gallery-themes | OK | 76.8 | 79.2 | 76.8 | none |  |
| Streamline Moderne | gallery-themes | HEAD-CUT | 94 | 31.0 | 26 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Strip Credits | gallery-themes | OK | 73 | 73 | 73 | none |  |
| Subway Diagram | gallery-themes | HEAD-CUT | 101 | 41.9 | 23 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Supergraphics | gallery-themes | HEAD-CUT | 93 | 31.0 | 25 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Suprematism | gallery-themes | HEAD-CUT | 153 | 41.9 | 75 | partly hidden, optional | painted content starts at 42px, under the 62px cover |
| Swiss International | gallery-themes | HEAD-CUT | 73 | 31.0 | 5 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Symmetry Pastel Hotel | gallery-themes | HEAD-CUT | 117 | 41.9 | 39 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Tape Crossing | gallery-themes | OK | 86.1 | 86.1 | 86.1 | none |  |
| Tape Strips | gallery-themes | OK | 93 | 93 | 93 | none |  |
| Tarot | gallery-themes | HEAD-CUT | 125 | 41.9 | 47 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Tattoo Flash | gallery-themes | HEAD-CUT | 117 | 41.9 | 39 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Techno Corporate | gallery-themes | HEAD-CUT | 88 | 30.0 | 20 | hidden, needed for clearance | painted content starts at 30px, under the 62px cover |
| Tiqoe Dark | gallery-themes | FAIL | 54.8 | 7.9 | 20.1 | hidden, needed for clearance | title starts at 55px |
| Tokyo Night | gallery-themes | HEAD-CUT | 88 | 41.9 | 10 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Tracked Mist | gallery-themes | OK | 81 | 81 | 81 | none |  |
| Tschichold Paperback | gallery-themes | HEAD-CUT | 105 | 31.0 | 37 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| Twilight | gallery-themes | HEAD-CUT | 76.9 | 28.9 | 42.1 | partly hidden, needed for clearance | painted content starts at 29px, under the 62px cover |
| Ukiyo-e | gallery-themes | HEAD-CUT | 97 | 41.9 | 19 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Undercity Dusk | gallery-themes | HEAD-CUT | 102.1 | 47 | 26.6 | partly hidden, needed for clearance | painted content starts at 47px, under the 62px cover |
| Underground Comix | gallery-themes | HEAD-CUT | 102 | 41.9 | 24 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Upvote | gallery-themes | OK | 78.8 | 78.8 | 78.8 | none |  |
| VHS Tracking Glitch | gallery-themes | HEAD-CUT | 117.6 | 41.9 | 39.6 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Verdana Revival | gallery-themes | HEAD-CUT | 129.8 | 0 | 35 | hidden, needed for clearance | painted content starts at 0px, under the 62px cover |
| Vermilion Cap | gallery-themes | OK | 111 | 111 | 111 | none |  |
| Vintage Letter Green | gallery-themes | HEAD-CUT | 76.6 | 27 | 50 | hidden, needed for clearance | painted content starts at 27px, under the 62px cover |
| Vorticist Blast | gallery-themes | HEAD-CUT | 92 | 31.0 | 24 | hidden, needed for clearance | painted content starts at 31px, under the 62px cover |
| WPA Screenprint | gallery-themes | HEAD-CUT | 170 | 31.0 | 102 | hidden, optional | painted content starts at 31px, under the 62px cover |
| Wake Square | gallery-themes | OK | 94 | 76 | 94 | none |  |
| Watch Later | gallery-themes | OK | 171 | 171 | 171 | none |  |
| Watercolor Wash | gallery-themes | HEAD-CUT | 110 | 40.9 | 32 | partly hidden, needed for clearance | painted content starts at 41px, under the 62px cover |
| Wiener Werkstätte | gallery-themes | HEAD-CUT | 145 | 40.9 | 67 | partly hidden, needed for clearance | painted content starts at 41px, under the 62px cover |
| Wild West Wanted Poster | gallery-themes | HEAD-CUT | 105 | 41.9 | 27 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Zellige | gallery-themes | HEAD-CUT | 127 | 41.9 | 49 | partly hidden, needed for clearance | painted content starts at 42px, under the 62px cover |
| Liquid Glass Aurora | arch | HEAD-CUT | 96 | 11 | 28 | hidden, needed for clearance | painted content starts at 11px, under the 62px cover |
| Liquid Glass Clear | arch | HEAD-CUT | 96 | 11 | 28 | hidden, needed for clearance | painted content starts at 11px, under the 62px cover |
