# Third-Party Notices

Nectar is a fork of [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire)
and is itself MIT-licensed (see [`LICENSE`](./LICENSE)). This file aggregates
attributions for third-party code, article themes, and fonts referenced
throughout the codebase.

## Base project

| Project | License | Used for |
| --- | --- | --- |
| [Ranchero-Software/NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire) | MIT | Nectar's base fork. |
| [kyrielie/ambrosia](https://github.com/kyrielie/ambrosia) | MIT | Companion JSON Feed–based backend Nectar is repointed at. |

## AO3 tooling (reference only)

Nectar is a read-only AO3 client. It does not run, embed, or link against
any of otwarchive's code, and none of the tools below were copied from —
each entry states exactly what was checked and why.

| Project | License | Used for |
| --- | --- | --- |
| [otwcode/otwarchive](https://github.com/otwcode/otwarchive) | GPL-2.0-or-later | Markup structure reference only, to understand AO3's own page structure when writing Nectar's HTML extractors. |
| [nianeyna/ao3downloader](https://github.com/nianeyna/ao3downloader) | GPL-3.0 | Selectors in `AO3SearchResultsExtractor.swift`, `AO3SeriesListingExtractor.swift`, `AO3ListingPagination.swift`, and `ArticleCSVExporter.swift` were cross-checked against this tool's parsing approach — see the in-code comments at each site for specifics. |
| [ArmindoFlores/ao3_api](https://github.com/ArmindoFlores/ao3_api) | MIT | Cross-checked for `AO3ChapterHTMLExtractor.swift`'s `authenticity_token` handling and `AO3KudosRequest.swift`'s kudos endpoint. |

## Article themes (`.nnwtheme`)

Full detail for each theme lives in its own `Themes/<Name>.nnwtheme/License.md`
where one exists. 

| Theme(s) | Source | License |
| --- | --- | --- |
| Ember | [emmsdibs/ao3-darkred](https://github.com/emmsdibs/ao3-darkred) | GPLv3 |
| Beetlejuice | [NCFC-Wiki/Beetlejuice-theme-for-AO3](https://github.com/NCFC-Wiki/Beetlejuice-theme-for-AO3) | MIT |
| Black & White, Charcoal Rose, Dusky Purple, Midnight Teal, Powder Pink, Tumblr Blue | [ZerafinaCSS/neos](https://github.com/ZerafinaCSS/neos) | MIT |
| Dracula | [dracula/archive-of-our-own](https://github.com/dracula/archive-of-our-own) | MIT |
| Rosé Pine, Rosé Pine Dawn, Rosé Pine Moon | [Wolfbatcat/ao3-rose-pine](https://github.com/Wolfbatcat/ao3-rose-pine) | |
| Vintage Letter Green | [Wolfbatcat/Vintage-Letter-Green-AO3-Skin](https://github.com/Wolfbatcat/Vintage-Letter-Green-AO3-Skin) | MIT |
| Moonlit Wisteria, Pastel Whimsy, Poudre et Plume | intothisshadow ([github](https://github.com/intothisshadow)) | |
| Constellations | [thevalkyrieismakingao3skinsig/constellations-ao3-skin](https://github.com/thevalkyrieismakingao3skinsig/constellations-ao3-skin) | |
| Broadsheet | [stuartbreckenridge/NNWThemesBroadsheet](https://github.com/stuartbreckenridge/NNWThemesBroadsheet) | |

## Fonts

Themes using a `@import` from Google Fonts (Aldine, Deco Line, Hyperlegible,
Kelmscott, Kennerley, Marigold Press, Moonlit Wisteria, Pastel Whimsy, Poudre
et Plume, Rosarivo) pull the font at render time under each font's own open
license (SIL Open Font License for most Google Fonts entries); no font files
are bundled in this repository. NewsFax bundles the ModeSeven font directly —
see `Themes/NewsFax.nnwtheme/License.md`.

