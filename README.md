# Nectar

Nectar is an iOS client for [Ambrosia](https://github.com/kyrielie/ambrosia), a JSON
Feed–based backend for quickly browsing a local fanfiction library. It reads a JSON Feed
extension (`_ambrosia`) that carries fic-specific metadata — word count,
chapter progress, fandom, rating and warnings, series — and surfaces it
directly in the timeline and article view.

Nectar is a fork of [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire)
and reuses a substantial amount of its code, but it is not affiliated with or
supported by the NetNewsWire project.

## Status

This is beta software under active development. Expect rough edges.

## Scope

Nectar can parse Ambrosia paged JSON feeds and sqlite transfers. It is not meant to be general-purpose
feed reader, but technically it should be functional with any RSS/JSON feed.

- If you don't use Ambrosia, use [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire) instead.
- If you do use Ambrosia, Nectar can also read its plain feeds — it just adds
  the fic-reader metadata on top when available.

## Features

- **Fic-aware timeline and article view** — word count, chapter progress,
  completion status, fandom, relationships, characters, ratings, warnings,
  categories, and series are read from the `_ambrosia` JSON Feed extension
  and shown as metadata lines/badges on each card, alongside a reading
  progress bar derived from scroll position.
- **Markdown content** — items can carry a Markdown body instead of HTML;
  Nectar renders it to HTML for display.
- **Book identity across duplicates** — duplicate works or works subscribed to through
  more than one collection feed is recognized as the same book based on AO3 id. Marking it
  read, starred, or Loved, or updating its reading progress, applies to
  every copy at once.
- **Loved**, in addition to the usual Read and Starred (Read Later) states,
  with its own smart feed and heart indicator.
- **Timeline Layout customization** — summary line count and metadata and tag previews are
  adjustable from Settings, with a live preview.
- **Reader theme overrides** — normal reader features, now built into the application.

## Architecture

See [`nectar-architecture.md`](./nectar-architecture.md) for how feed data
flows from Ambrosia's JSON Feed extension through to the app's UI.

## License

Nectar is available under the same license as NetNewsWire — see
[`LICENSE`](./LICENSE).
