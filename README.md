# Nectar

Nectar is an iOS client for [Ambrosia](https://github.com/kyrielie/ambrosia), a JSON
Feed–based backend for quickly browsing a local fanfiction library. It reads a JSON Feed
extension (`_ambrosia`) that carries fic-specific metadata — word count,
chapter progress, fandom, rating and warnings, and series — and surfaces it
directly in the timeline and article view.

Nectar is a fork of [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire)
and reuses a substantial amount of its code, but it is not affiliated with or
supported by the NetNewsWire project.

## Status

This is beta software under active development. Expect rough edges.

## Scope

Nectar only speaks the Ambrosia JSON Feed dialect. It is not a general-purpose
feed reader:

- If you don't use Ambrosia, use [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire) instead.
- If you do use Ambrosia, Nectar can also read its plain feeds — it just adds
  the fic-reader metadata on top when available.

## Architecture

See [`nectar-architecture.md`](./nectar-architecture.md) for how feed data
flows from Ambrosia's JSON Feed extension through to the app's UI.

## License

Nectar is available under the same license as NetNewsWire — see
[`LICENSE`](./LICENSE).
