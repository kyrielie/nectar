# Guide

An in-app, static walkthrough reachable from Settings → Help → Guide
(`SettingsViewController`'s `HelpRow.guide`). Not onboarding — it doesn't
run automatically and isn't gated on first launch or an empty account;
it's a reference the person opens deliberately, any number of times.

## Architecture

Two choices were weighed for how the guide sits over the app:

1. **A full-screen sheet or its own navigation stack**, covering
   Settings entirely while it's open.
2. **A transparent, dismissible overlay presented on top of the real
   Settings screen**, which stays visible (dimmed, untappable) behind it —
   the approach taken.

(2) won because the reference mockup's whole visual idea — the dialogue
box floating over a visible, real backdrop like a visual-novel
overlay — depends on that backdrop actually being there, not a
placeholder screenshot. `GuideOverlayView` is presented
`.overFullScreen` from `SettingsViewController` (see
`settings-screen.md`), matching the existing
`MainFeedCollectionViewController.openInAppBrowser()` precedent for
that presentation style over the default `.pageSheet`. `.overFullScreen`
is what makes this possible with no extra hit-testing work: a modally
presented view controller receives all touches by default, so Settings
showing through the scrim needs no explicit "disable interaction"
handling.

## Content

`GuideContent.pages` is a static, hand-maintained `[GuidePage]` array —
there's no backend or CMS. Each page has a stable `id`, a `title`, and a
`body` string. Whoever ships a feature that deserves a Guide page adds
it to this array in the same PR; nothing enforces that, so pages can
drift behind the features they describe if that convention isn't
followed by hand.

## No seen/unseen tracking

Deliberately not implemented in this pass. A version was drafted using
`AppDefaults` to store the `id` of the last page shown and compare it
against `GuideContent.pages.last?.id`, to drive a badge dot on the
Settings row when new pages had been added since the person last opened
Guide (the reference mockup's `.badge-dot` element). It was dropped
because a single last-seen marker doesn't handle someone who's read
pages 1-2 out of a 4-page guide, then two more pages get added later —
there's no way to tell "seen everything up to page 2" apart from "seen
nothing," so the badge would either under- or over-fire depending which
half of that gap you're in. Revisiting this needs a set of seen page
IDs, not a single watermark; out of scope here. The Settings row is
plain — no badge, no dot — until that's built properly.

## Visual implementation notes

`GuideOverlayView`'s palette (`GuideTheme`) is lifted directly from the
approved reference mockup's CSS custom properties, both light and dark
values. It's local to this one file — nothing else in the app uses this
specific cream/brown/green palette, so it isn't promoted to a shared
design-system type.

The dialogue box's flat, offset "3D" bottom edge (the reference's
`box-shadow: 0 8px 0 var(--box-border-dark)`) is drawn as a second,
solid-filled `RoundedRectangle` positioned behind and below the box,
since SwiftUI's `.shadow` modifier only produces blurred shadows and
can't reproduce a hard-edged offset like this.

Text reveals character-by-character via a `Task`-driven counter
(22ms/character, matching the reference's `setInterval` cadence
exactly) rather than any per-character animation — tapping the box
mid-reveal cancels the task and jumps straight to the full string; a
second tap once fully revealed advances to the next page, or dismisses
on the last page. The blinking cursor (`TypewriterCursor`) uses its own
timer-backed toggle rather than SwiftUI's implicit `.animation`, since
CSS's `steps(1)` hard-cut blink isn't expressible through interpolated
animation on a single `Bool`.

No mascot is shown in this pass. The reference mockup includes one; the
space above the dialogue box is intentionally left empty rather than
filled with placeholder art.
