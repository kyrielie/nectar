# Terminology

Nectar was forked from an RSS reader and is now a fanfiction library
client. The user interface uses library vocabulary; the code, the
database, and these docs still use the RSS-reader vocabulary the fork
inherited. Both are correct in their own place. This doc says which
vocabulary belongs where, so new copy is written consistently and code
isn't renamed by accident.

Only what a reader sees changed: `NSLocalizedString`/`Text(...)` literals,
storyboard text, and the string catalogs. Symbols, types, `AppDefaults`
keys, notification names, file names, and the other docs in this folder
are unchanged.

## UI vocabulary versus code vocabulary

| Concept | Shown to the reader | Code and docs |
| --- | --- | --- |
| Top-level screen | "Your archive" | the sidebar (`MainFeedCollectionViewController`) |
| The on-device account (default name) | "Library" | `AccountType.onMyMac`, `Account.defaultName` |
| Today/Unread/Starred/Loved group | "Smart shelves" | `SmartFeedsController`, smart feeds |
| One tracked source (a tag, search, author, bookmarks list, series) | "Shelf" | `Feed` |
| Folder | "Folder" | `Folder` (unchanged) |
| One reading unit, in almost every context | "Work" | `Article` |
| One reading unit, only in the Annotations scope picker | "Chapter" | `Article` (`articleID`) |
| A whole multi-chapter story | "Work" | `bookKey` ("book" in code) |

The default for reading actions is "Work", not "Chapter". Each action acts
on one `articleID`, but most fics are single-chapter, and a reader thinks
of themselves as reading a work. "Chapter" appears in exactly one place;
see the next section.

New copy about the reading screen (`ArticleViewController`,
`WebViewController`) should say "work". No on-screen string says
"Article view"; this is guidance for whoever writes the next one.

A note on the shipped strings: catalog keys in `Localizable.xcstrings` are
the English source text, and the app is English-only. Renaming a string
therefore means renaming its key. When a key is still used elsewhere (see
"What stays in RSS terminology on purpose"), the old entry stays and the
new one is added beside it.

## Import Link and Import AO3 Links

Two adjacent items in the sidebar's add menu look alike and do different
things:

- **Import Link** opens `AddFeedViewController`. It is the general
  entry point: one URL, an optional title, a folder. What is pasted is
  either an AO3 listing page (tag results, search results, an author's
  works, bookmarks, marked-for-later, subscriptions, collections, series)
  or an ordinary RSS/Atom URL that goes through feed autodiscovery.
  Either way the result is a shelf that keeps refreshing.
- **Import AO3 Links…** opens `AO3LinkListImportView`. It is the specific
  entry point: pasted text containing individual work links, imported
  once. The result is not a shelf and does not refresh; its own footer
  says so.

The difference the pair has to teach is subscribe versus one-time import.
Keep "Import" for both and let "Link" versus "AO3 Links…" carry the
distinction. Don't reuse "Import" for a third action that does neither.

## The one exception: Annotations' scope picker

`AnnotationsListView`'s tab switcher is the single place in the app
where "Chapter" and "Work" both appear, because it's solving a
different problem than the reading-action vocabulary above: it's a
scope filter for *reviewing your own highlights*, not a way of
navigating between reading units. Opened mid-read on a multi-chapter
work, **"This Chapter"** shows only what you highlighted on the page
currently open (`Scope.chapter(articleID:bookKey:)`) — so reviewing
your highlights doesn't mean scrolling past every other chapter's marks
to find the one you want. **"This Work"** shows everything you've
highlighted across every chapter sharing that `bookKey` — for reviewing
or referencing the whole story once you're caught up or finished. Two
different real moments (quick in-context lookup vs. comprehensive
after-the-fact review), not two names for one concept.

The distinction only actually does anything for multi-chapter works —
for a single-chapter fic (most of them), both tabs show identical
content, since there's only one article. And "This Chapter" isn't a
precise narrative boundary: the code's own comment flags that
`chapterTitle` (the heading nearest a highlight) doesn't always align
1:1 with `articleID` — one loaded article can contain more than one
heading, or one narrative chapter can span more than one article,
depending on how the feed delivered it. "This Chapter" really means
"the article currently open behind this screen," which usually but not
always corresponds to one actual chapter — a known, called-out
simplification, not something this doc is claiming is exact.

Everywhere else in the app, default to "Work" per the table above —
don't introduce "Chapter" elsewhere just because it exists here; the
reasoning above is specific to this one filtering UI, not a general
preference for chapter-level granularity.

## What stays in RSS terminology on purpose

Screens for diagnosing or maintaining the app keep the RSS vocabulary,
because their audience is already thinking about feeds, response codes,
and network requests. Confirmed by reading the code:

- **`DinosaursView`** (Settings → stale feeds): "Delete Feed",
  "Go to Feed", "Copy Feed URL", and its delete confirmation are
  unchanged. It shares catalog keys with reader-facing code, which is why
  the old "Delete Feed", "Go to Feed", and "Copy Feed URL" entries were
  kept when the new keys were added.
- **The Activity Log and Error Log**, and their operation names
  ("Refreshing feed", "Subscribing to feed", "Feed Finder"). The
  Activity Log lives in its own module with its own catalog.
- **The Account Stats explainer** that describes the article,
  feed-settings, and sync-queue databases.
- **Raw strings that only reach logs**, such as the `NSError` description
  built in `LocalAccountRefresher` for a listing that needs sign-in. The
  reader-facing twin of that message says "shelf".
- **AO3's own RSS feeds.** "About Tag & User Feeds" and its body describe
  what AO3 publishes, not a shelf, so they still say "feed".
- **"OPML"**, a real file-format standard: "Import OPML File",
  "Export OPML File".
- **Export filenames on disk**: `Subscriptions-<AccountName>.opml`,
  `Articles-<AccountName>.csv`/`.sqlite`, `Highlights-<AccountName>.csv`.
  They are read by other tools and by later imports, so they are not
  renamed.
- **The `feed:` and `feeds:` URL schemes.**

When you are unsure whether "feed" refers to the reader's shelf or to a
real RSS/Atom feed, ask what the reader is looking at. If it is their own
tracked source, write "shelf". If it is AO3's RSS output or a debug
surface, "feed" is accurate.

## Behavior the copy has to match

**Deleting a shelf does not delete every work on it.**
`LocalAccountDelegate.removeFeed` only removes the feed from the account
tree. The works are cleaned up on the next launch by
`ArticlesTable.deleteArticlesNotInSubscribedToFeedIDs`, which removes only
works from unsubscribed feeds that are unread, not starred, not loved,
and have no reading progress. Anything the reader has read, starred,
loved, or started stays. The delete confirmation says exactly this;
don't shorten it to "your works are kept", which is false for untouched
works.

**The default account name is resolved live.** `Account.nameForDisplay`
falls back to `defaultName` (from `AccountType.displayName`, which reads
`account.name.on-my-device` in `DefaultAccountNames.xcstrings`) whenever
the account has no custom name. Changing that catalog value renames the
account for existing installs that never customized it.

## Wording that is still ambiguous

Not decided; noted so it isn't rediscovered by accident.

- A shelf's context menu now has "Copy Link" (the shelf's own URL) beside
  "Copy Home Page URL" and "Open Home Page". A reader cannot tell from
  the labels what differs between them. The Home Page items were not part
  of the rename.
- The Add screen (`Add.storyboard`) has a scene titled "Feed Folder"
  (`AddFeedFolderViewController`). The visible navigation title on that
  screen is "Select Folder", so the scene title does not appear, and it
  was left alone.
- `Account.storyboard` contains an iCloud account scene whose footer
  still says "feeds". `CloudKitAccountNavigationViewController` is not
  instantiated anywhere in Swift, so the scene appears unreachable. Not
  confirmed at runtime.
- `AO3LinkListImportView.swift` has a code comment that still says
  "Collections". It is a comment, not a string, so it was left alone.
