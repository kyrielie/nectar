# Building an IPA for Sideloadly (Free Apple ID / Personal Team)

These steps produce a signed `.ipa` without going through Xcode's "Distribute
App" flow, which fails on a free Apple ID with:

> Team "Your Name (Personal Team)" is not enrolled in the Apple Developer
> Program. Distribution requires enrollment in the Apple Developer Program.

That check happens during Organizer's distribution *analysis* step, not
during archiving itself -- the archive already contains a validly-signed
`.app`. We just skip Distribute App and package the IPA by hand.

## Prerequisites (one-time setup)

- `DeveloperSettings.xcconfig` must exist at
  `<repo root's parent>/SharedXcodeSettings/DeveloperSettings.xcconfig`
  (a sibling of the folder containing `NetNewsWire.xcodeproj`, **not** inside
  it), containing at least:

  ```
  DEVELOPER_ENTITLEMENTS = -dev
  DEVELOPMENT_TEAM = <your Team ID>
  ```

  This points code signing at `Nectar-dev.entitlements` (App Groups +
  Keychain Sharing) instead of `Nectar.entitlements` (which requires paid
  enrollment for its iCloud capability).

- Verify it's actually being picked up before archiving:

  ```bash
  cd /path/to/nectar
  xcodebuild -showBuildSettings -project NetNewsWire.xcodeproj -target Nectar-iOS \
    | grep -E "CODE_SIGN_ENTITLEMENTS|DEVELOPER_ENTITLEMENTS|DEVELOPMENT_TEAM"
  ```

  Expect:
  ```
  CODE_SIGN_ENTITLEMENTS = iOS/Resources/Nectar-dev.entitlements
  DEVELOPER_ENTITLEMENTS = -dev
  DEVELOPMENT_TEAM = <your Team ID>
  ```

## Every release

1. **Set the destination.** In Xcode's toolbar, choose **"Any iOS Device
   (arm64)"** as the run destination (not a simulator, not your physical
   device directly).

2. **Archive.** Product → Archive. Wait for the Organizer window to open
   automatically with the new archive selected.

3. **Do NOT click "Distribute App."** It will fail with the enrollment
   error above regardless of which distribution method you pick (App Store
   Connect, Release Testing, Debugging, Custom -- all of them).

4. **Reveal the archive in Finder.** Right-click the archive in Organizer →
   **"Show in Finder."**

5. **Open the archive package.** Right-click the `.xcarchive` file →
   **"Show Package Contents."**

6. **Find the app bundle.** Navigate to `Products/Applications/` inside the
   package. You should see `Nectar.app`.

7. **Build the IPA by hand.** Open Terminal:

   ```bash
   cd "/path/to/that/Applications/folder"
   mkdir Payload
   cp -R Nectar.app Payload/
   zip -r Nectar.ipa Payload
   ```

   `Nectar.ipa` now sits in that same folder.

8. **Install with Sideloadly.** Drag `Nectar.ipa` into Sideloadly, sign in
   with your Apple ID, and install to your connected iPhone. Sideloadly
   re-signs the IPA itself during install, so the exact signature from step
   7 doesn't need to be perfect -- it just needs a valid `.app` bundle
   structure, which the archive already provides.

## Notes

- Free Apple ID certs expire roughly every 7 days. You'll need to
  reinstall via Sideloadly (repeat step 8, no rebuild needed) when the app
  stops opening.
- If `DEVELOPMENT_TEAM` ever reverts to a stale/wrong value, check
  `project.pbxproj` for hardcoded `DEVELOPMENT_TEAM = ...` lines under the
  target's build configurations -- these override the xcconfig include and
  may need a manual find-and-replace.
