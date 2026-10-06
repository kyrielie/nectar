# Release pipeline

Releases are cut by running **Release IPA and source** (`.github/workflows/release.yml`) with
`workflow_dispatch`. It builds an unsigned IPA, attaches it to a GitHub release, and merges a new entry
into `source.json` on `gh-pages` (the AltStore-style source).

## Running it

Inputs: `tag` (required, `vX.Y.Z`), `source_ref` (default `main`, used only when the tag does not exist
yet), `prerelease` (applies only when the release is created by this run).

Jobs, in order:

1. `prepare-tag` (ubuntu): validates the tag against `^v[0-9]+\.[0-9]+\.[0-9]+$` (the tag minus `v` becomes
   `MARKETING_VERSION`, so a suffix would reach `CFBundleShortVersionString`). If the tag exists it is
   reused and `source_ref` is ignored; otherwise it is created at `source_ref`'s commit and pushed.
   Outputs the commit SHA.
2. `build-ipa-release` (macos): checks out that SHA, archives, and runs `gh release create ... --verify-tag`
   (or `gh release upload --clobber` if the release exists).
3. `publish-source` (also fires on `release: edited`): checks out the tag, merges `source.json`, syncs the
   icon and `appstore/screenshots`, pushes to `gh-pages` with a rebase-and-retry loop.

Before `prepare-tag` existed, the tag had to exist first, because the build job checked out `inputs.tag`
before anything created it; the workaround was an empty release to mint the tag.

Tags pushed with `GITHUB_TOKEN` do not start other workflows (GitHub's rule for events caused by that
token, other than `workflow_dispatch`/`repository_dispatch`). Nothing here depends on a tag-push trigger.

## gh-pages concurrency

`gallery.yml` (daily and on path changes) and `publish-source` both push to `gh-pages`. Both use
rebase-and-retry. A `concurrency:` group was not used on `release.yml` because a pending run in a group
is replaced by a newer one, which could drop a release publish.

## Screenshots in the source

`scripts/update_source.py --screenshots-dir=<dir>` replaces the template app's `screenshots` list with the
image files in `<dir>` in natural order (`2.png` before `10.png`), rooted at the template `iconURL`'s
directory. With no usable directory the template's list is kept. The symlink guard (`release.yml` sync
step and the `appstore-assets` job in `ci.yml`) exists because `cp -R` copies symlinks as symlinks, which
dangle on `gh-pages`. Producing the files: see `ui-test-demo-data.md` (App Store screenshots).

## Not done

`.github/release.yml` (release-note categories) was not added; its schema was not verified. A bump mode
(compute the next version from the latest tag) was not added.
