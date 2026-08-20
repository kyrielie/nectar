<div align="center">

# 🍎 Nectar

<img width="100" height="100" alt="Nectar Icon" src="https://github.com/user-attachments/assets/8af38915-340c-4106-be1e-703983852ba9" />


**An iOS feed reader for Archive of Our Own and [Ambrosia](https://github.com/kyrielie/ambrosia). An unofficial AO3 reading application. **

[![Install via AltStore](https://img.shields.io/badge/AltStore-Install-4185A9?style=for-the-badge)](https://kyrielie.github.io/nectar/source.json)
[![Latest release](https://img.shields.io/github/v/release/kyrielie/nectar?style=for-the-badge&label=release)](https://github.com/kyrielie/nectar/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/kyrielie/nectar/ci.yml?branch=main&style=for-the-badge&label=CI)](https://github.com/kyrielie/nectar/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=for-the-badge)](./LICENSE)

## Quick Install
<h3 align="center">
<a href="https://altdirect.app/?url=https://altdirect.app/?url=https://kyrielie.github.io/nectar/source.json"><img src="https://altdirect.app/assets/png/AltSource_Blue.png" target="_blank" width="200">
</a>
</h3>
</div>

> [!IMPORTANT]
> Before continuing, please read the AO3 admin post [Why AO3 Doesn't Have an Official App](https://archiveofourown.org/admin_posts/35806) and be aware of [the history of unofficial apps that accessed AO3 on fanlore](https://fanlore.org/wiki/AO3_App_Wars). Please be aware that it is recommended to use AO3 in your browser. This app does not require you to log in using your account. Be aware that "**if you log in to AO3 on these apps, (like Nectar) the apps' developers may gain access to your username and password. You're trusting both that the developer is not malicious and that they have taken all proper precautions to keep your login information safe. If your login information is exposed to someone with malicious intent, they could log into your account to post Terms of Service-violating content, delete your works, change your account's credentials so you can't log in, or even delete your account.**" (from AO3 admin post).

- [x] This app will always be free and open source. (If you don't trust me, you can look at the code and build the application yourself.)
- [x] This app does not distribute fics. 
- [x] This app does it's best to respect AO3's TOS, servers, and policies.
- [x] Nectar logs you in using the Safari browser. Your login details stay on your phone.
- [x] Your reading history stays private on your phone.

## Background

Nectar was originally designed to read Archive of Our Own's [RSS feeds](https://archiveofourown.org/faq/subscriptions-and-feeds?language_id=en#subscribetag) however AO3's RSS feeds are limited by design. The feed contains only the most recently updated works and provides only links to AO3 and restricted works aren't included. Any feed reader can read an RSS feed, Nectar just follows the link and provides a better reading experience.

Knowing the controversy about AO3 client applications, I originally limited Nectar to being a companion app for [Ambrosia](https://github.com/kyrielie/ambrosia), a local fanfiction library that hosts a JSON Feed extension (`_ambrosia`) carrying fic-specific metadata — word count, chapter progress, fandom, rating, warnings, series, and book identity — for my large personal collections of epubs that I downloaded from AO3. 

I have extended the functionality of Nectar to be able to update the metadata and text from AO3 for my local library. Now you can load any work search link and start reading. 

Use AO3 in your browser to filter works, copy the url and paste it as a feed in Nectar. Alternatively, load any list of AO3 links to import your current tabs. Nectar caches any work you've opened in it, saving all fics you've read and preventing you from losing your progress. It load each work's full text with the creator's own style enabled, so it feels like opening AO3 in a browser — but with saved reading position, offline-friendly caching, and a distraction-free reader. 

Nectar is a fork of [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire) and uses its code and license, but is not affiliated with or supported by the NetNewsWire project. It is not associated with Archive of Our Own; it makes requests to AO3's servers only when you open a work. Your reading history and progress stay on your device and are never shared.

> **Status:** beta software under active development. Expect rough edges. 

---

## Contents

- [Features](#features)
- [Installation](#installation)
  - [AltStore (recommended)](#altstore-recommended)
  - [Sideloadly](#sideloadly)
  - [Building from source](#building-from-source)
- [Scope](#scope)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Fic-aware timeline and article view** — word count, chapter progress, completion status, fandom, relationships, characters, ratings, warnings, categories, and series are read from AO3/Ambrosia and shown as metadata lines and badges on each card, alongside a reading-progress bar derived from scroll position.
- **Large-collection sync** — beyond ordinary JSON Feed fetching, Ambrosia collections can sync over a dedicated paginated SQLite transfer route built for large libraries that would be impractical over plain HTTP JSON.
- **Book identity across duplicates** — the same work showing up in more than one collection feed, or re-imported from Calibre, is recognized as one book. Marking it read, starred, or Loved, or updating reading progress, applies to every copy at once and survives unsubscribing/re-subscribing.
- **Live AO3 chapter fetching** — in-progress works can fetch new chapters on demand, with per-host rate-limit backoff and a regression guard that refuses to overwrite good content with a bad/short fetch.
- **Markdown content** — items can carry a Markdown body instead of HTML; Nectar renders it for display.
- **Loved**, alongside the usual Read and Starred (Read Later) states, with its own smart feed and heart indicator.
- **Timeline layout customization** — icon size, summary line count, and metadata/tag previews are adjustable from Settings, with a live preview.
- **Reader theming** — Accent Color and Surface Palette let you retint the app's chrome independently of the article reader's own theme, with a matching set of bundled `.nnwtheme`s.
- **Annotations and highlights** - save quotes, write notes. 

## Installation

Nectar isn't on the App Store — it's distributed as an unsigned IPA you sideload yourself. There are many ways to sideload, but these are the only ones that I test:

### AltStore (recommended)

1. Install [AltStore](https://altstore.io) (or [SideStore](https://sidestore.io)) if you haven't already, and pair it with your Apple ID. *Sideloading installs applications to your phone using developer signing, so you will need to set up a server to approve the app. Follow the AltStore Classic or SideStore installation instructions. AltStore Classic requires a computer with AltServer installed.*
2. Add Nectar's source:

   ```
   https://kyrielie.github.io/nectar/source.json
   ```

3. Install **Nectar** from the source. AltStore will surface new releases here automatically going forward.

*You can only install 3 sideloaded apps by default. Use [LiveContainer](https://github.com/LiveContainer/LiveContainer) to install additional apps.*

### Sideloadly

If you'd rather install a single release without adding a source:

1. Download the latest `Nectar-unsigned.ipa` from [the Releases page](https://github.com/kyrielie/nectar/releases/latest).
2. Install [Sideloadly](https://sideloadly.io) and connect your device.
3. Drag the IPA into Sideloadly, sign in with your Apple ID, and install. Sideloadly re-signs the unsigned IPA during install.
4. With a free Apple ID, the app's signature expires after about 7 days — reinstall the same IPA through Sideloadly when it stops opening (no rebuild needed). A paid Apple Developer account extends this to a year.

### Building from source

Building your own signed IPA (useful if you want to build off `main` rather than the latest tagged release) is documented in [`docs/building-an-ipa-for-sideloadly.md`](./docs/building-an-ipa-for-sideloadly.md). In short:

```bash
git clone --recursive https://github.com/kyrielie/nectar.git
cd nectar
brew install xcodegen
xcodegen generate
open NetNewsWire.xcodeproj
```

Requires Xcode with an iOS 17+ SDK and the `Nectar-iOS` scheme.

## Architecture

Nectar is built on top of NetNewsWire to take advantage of feed reading capability. It isn't meant to be a general-purpose feed reader, though it should technically work with any RSS/JSON feed. However it is designed to be archival, so there's no way to automatically delete things in the cache, so if you add newspapers the storage will be unmanageable. 

See [`CLAUDE.md`](./CLAUDE.md) for the docs index — how feed data flows from AO3/Ambrosia through to the app's UI is split across topic docs under `docs/` (module layout, book identity, the SQLite transfer route, the reading-progress pipeline, the theming system, and more), each scoped to one system.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) before opening a PR.

## Acknowledgments

Nectar's AO3 HTML extractors were cross-checked against (not ported from)
[nianeyna/ao3downloader](https://github.com/nianeyna/ao3downloader) (GPL-3.0)
and [ArmindoFlores/ao3_api](https://github.com/ArmindoFlores/ao3_api) (MIT),
and reference [otwarchive](https://github.com/otwcode/otwarchive)'s own
markup structure (GPL-2.0-or-later) for context. Several bundled article
themes are inspired by community AO3 workskins — see
[`THIRD-PARTY-NOTICES.md`](./THIRD-PARTY-NOTICES.md) for the full list of
sources and licenses, including per-theme detail in each theme's own
`Themes/*/License.md`.

## License

Nectar is available under the same license as NetNewsWire — see [`LICENSE`](./LICENSE) (MIT).
