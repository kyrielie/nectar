# Release pipeline

Releases are cut by running **Release IPA and source** (`.github/workflows/release.yml`) with
`workflow_dispatch`. It builds an unsigned IPA, attaches it to a GitHub release, and merges a new entry
into `source.json` on `gh-pages` (the AltStore-style source).

## Running it

Inputs: `tag` (required, `vX.Y.Z`), `source_ref` (default `main`, used only when the tag does not exist
yet), `prerelease` (applies only when the release is created by this run).

Jobs, in order:

1. `prepare-tag` (ubuntu): validates the tag against `^v[0-9]+\.[0-9]+\.[0-9]+$` (the tag minus `v` becomes
   `MARKETING_VERSION`, so a suffix would reach `CFBundleShortVersionString`). If the tag exists, its commit
   is used and `source_ref` is ignored; otherwise `source_ref`'s commit is used. Outputs that commit SHA and
   `tag_exists`. It pushes nothing.
2. `ci` (calls `ci.yml`): runs the whole suite on that SHA. See "Test gate" below.
3. `create-tag` (ubuntu): pushes the tag at that SHA if `tag_exists` is `false`. The job always runs on
   dispatch (only the push step is conditional), because a job whose needed job was skipped is skipped too,
   and `build-ipa-release` needs this one.
4. `build-ipa-release` (macos): checks out that SHA, archives, and runs `gh release create ... --verify-tag`
   (or `gh release upload --clobber` if the release exists).
5. `publish-source` (also fires on `release: edited`): checks out the tag, merges `source.json`, syncs the
   icon and `appstore/screenshots`, pushes to `gh-pages` with a rebase-and-retry loop. The `release: edited`
   path skips `prepare-tag`, `ci`, `create-tag` and `build-ipa-release`, so editing release notes runs no tests.

Before `prepare-tag` existed, the tag had to exist first, because the build job checked out `inputs.tag`
before anything created it; the workaround was an empty release to mint the tag. The push moved from
`prepare-tag` to `create-tag` so that a commit whose tests fail is never tagged (a rerun reuses an existing
tag and ignores `source_ref`).

## Test gate

`ci.yml` has no `pull_request` or `push` trigger. It runs only when `release.yml` calls it (`workflow_call`,
input `ref` = the SHA from `prepare-tag`) or when someone starts it by hand (`workflow_dispatch`, on the branch
chosen in the "Run workflow" dropdown). `test.sh` runs the iOS tests locally. Every checkout in `ci.yml` uses
`ref: ${{ inputs.ref || github.sha }}`, so a called run tests the commit being released, not the branch the
release run was started from.

Consequences:

- Pull requests and merges to `main` are not tested. A break surfaces when a release is cut, not when it lands.
- Any branch protection rule or ruleset that lists a `ci.yml` job as a required status check must be removed;
  the check never reports without a PR trigger.
- `ci.yml` has no `concurrency:` block (it used to cancel superseded PR runs). With `cancel-in-progress` a second
  run on the same ref could cancel a release's gate.
- The `theme-gallery` job no longer runs `--check-release-identity`: it was guarded by
  `github.event_name == 'pull_request'` and compared against the PR base. See `theme-gallery.md` for running it
  by hand.
- `gallery.yml` still publishes the landing page and gallery on pushes to `main` without waiting for CI. Its own
  `gallery/build.py` run performs the bundle checks; the `unittest` step and `upstream-compat` do not run there.
- What the simulator test job runs: the `Nectar-CI` plan with coverage off
  (`-enableCodeCoverage NO`; the plan keeps it on for local runs, nothing in the repo reads it).
  The heavy theme suites run only when theme-related files changed since the previous release tag,
  when there is no previous tag, or when the manual `theme_suites` input is true; the 31 XCTest
  performance tests are not in the plan. See `theme-testing.md` ("CI scope"). The same job runs
  `buildscripts/fail_on_warnings.sh` on the test log; the separate `ios-simulator-build` job that
  compiled the app a second time was removed. Because the test log also covers the test targets,
  test-target warnings now fail the gate.
- The gate runs before the IPA build, so a release takes as long as the slowest `ci.yml` job (the simulator test)
  longer than before. Running `ci` in parallel with the build would be faster, but the IPA would be attached to
  the release before the tests pass.

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
dangle on `gh-pages`. `gallery.yml` also copies `appstore/screenshots` to `gh-pages` when those files change on `main` (overwrite and add
only, same symlink guard), because `publish-source` alone only refreshes them at release time. It never deletes,
so a screenshot removed from the repo disappears at the next release, not before. Producing the files: see
`ui-test-demo-data.md` (App Store screenshots).

## Not done

`.github/release.yml` (release-note categories) was not added; its schema was not verified. A bump mode
(compute the next version from the latest tag) was not added.
