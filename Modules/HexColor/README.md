# HexColor

`UIColor` <-> CSS hex string conversion, plus WCAG contrast-ratio
comparison. Extracted from `ArticleThemeColorExtractor.swift`, where it
originated as a "kept internal, not private, so both call sites can
use it" utility -- its actual reach turned out to be 14 files across
the Accent Color / Surface Palette / Badge Color / Highlight Palette
systems, so it now lives here as its own micro-package rather than as
an internal extension riding along with the CSS-stylesheet scanner
that happens to also need it.

No dependencies beyond `UIKit`. Everything in this package is `public`.
