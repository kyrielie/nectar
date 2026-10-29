# Implementation Plan: Supporting iOS 16 in `main`

## 1. Overview & Architecture Strategy

This plan details how to backport Nectar to support **iOS 16.0** directly in `main`, referencing the verified work in `../nectar16/nectar/`.

### Guiding Principles
1. **Zero Degradation on iOS 17+**: Native iOS 17+ features (`registerForTraitChanges`, `ContentUnavailableView`, persistent identifier-scoped `WKWebsiteDataStore`) remain active on iOS 17+ runtimes.
2. **Centralized Shims over Scattered Checks**: Do not scatter `#available(iOS 17, *)` across view bodies. Use structured wrappers (`EmptyStateView`, `observeTraits`, `scrollClipDisabledIfAvailable`).
3. **Single Universal Binary**: By lowering `IPHONEOS_DEPLOYMENT_TARGET` to `16.0` in `main`, `.github/workflows/release.yml` automatically outputs an unsigned IPA compatible with iOS 16 through 18+ and publishes `min_os_version: 16.0` into `source.json`.
4. **Reconcile with Commit `83cc8e51c`**: The prototype in `nectar16` branched before `83cc8e51c` (which split `WebViewController.swift` into modular extension files). The implementing engineer must apply trait observer changes to the newly modularized files rather than blindly copying `nectar16`'s monolithic `WebViewController.swift`.

---

## 2. File Inventory

### A. New Files to Port from `../nectar16/nectar/`

| Source in `../nectar16/nectar/` | Destination in `nectar/` | Purpose |
|---|---|---|
| `iOS/UIKit Extensions/TraitChangeObserving.swift` | `iOS/UIKit Extensions/TraitChangeObserving.swift` | Polyfills `registerForTraitChanges` on iOS 16 via hidden `TraitChangeObserverView` |
| `iOS/Shared/EmptyStateView.swift` | `iOS/Shared/EmptyStateView.swift` | Polyfills `ContentUnavailableView` on iOS 16 with native styling on iOS 17+ |
| `iOS/Shared/ViewAvailability.swift` | `iOS/Shared/ViewAvailability.swift` | `scrollClipDisabledIfAvailable()` helper |
| `Modules/RSParser/Tests/RSParserTests/Feeds/ParsedItemMarkdownTests.swift` | `Modules/RSParser/Tests/RSParserTests/Feeds/ParsedItemMarkdownTests.swift` | Validates `ParsedItem` markdown storage without Tidemark rendering |
| `Tests/NetNewsWire-iOSTests/DinosaursViewModelObservationTests.swift` | `Tests/NetNewsWire-iOSTests/DinosaursViewModelObservationTests.swift` | Tests `ObservableObject` behavior on `DinosaursViewModel` |
| `Tests/NetNewsWire-iOSTests/EmptyStateViewTests.swift` | `Tests/NetNewsWire-iOSTests/EmptyStateViewTests.swift` | Tests empty state rendering |
| `Tests/NetNewsWire-iOSTests/StrictLimitConfirmationTests.swift` | `Tests/NetNewsWire-iOSTests/StrictLimitConfirmationTests.swift` | Tests pure confirmation logic for daily reading limits |
| `Tests/NetNewsWire-iOSTests/TraitChangeObservingTests.swift` | `Tests/NetNewsWire-iOSTests/TraitChangeObservingTests.swift` | Tests trait observer helper on iOS 16 and 17+ |

### B. Configuration & Build Files to Update

* `project.yml`: Update `deploymentTarget.iOS` from `"17.0"` to `"16.0"`.
* `xcconfig/NetNewsWire_project.xcconfig`: Update `IPHONEOS_DEPLOYMENT_TARGET` from `17.0` to `16.0`.
* `NetNewsWire.xcodeproj/project.pbxproj`:
  - Add build file and file references for `TraitChangeObserving.swift`, `EmptyStateView.swift`, `ViewAvailability.swift`, and the 4 new test files.
  - Drop Tidemark package dependency reference and framework link.
* `NetNewsWire.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`: Remove Tidemark pin.
* 21 `Modules/*/Package.swift` files: Change `.iOS(.v17)` to `.iOS(.v16)`:
  - `Modules/AO3Kit/Package.swift`
  - `Modules/Account/Package.swift`
  - `Modules/ActivityLog/Package.swift`
  - `Modules/AnnotationsKit/Package.swift`
  - `Modules/AppChrome/Package.swift`
  - `Modules/ArticleTheming/Package.swift`
  - `Modules/Articles/Package.swift`
  - `Modules/ArticlesDatabase/Package.swift`
  - `Modules/BackupRestore/Package.swift`
  - `Modules/ErrorLog/Package.swift`
  - `Modules/FeedFinder/Package.swift`
  - `Modules/HTMLMetadata/Package.swift`
  - `Modules/HexColor/Package.swift`
  - `Modules/Images/Package.swift`
  - `Modules/RSCore/Package.swift`
  - `Modules/RSDatabase/Package.swift`
  - `Modules/RSParser/Package.swift` (also drop Tidemark dependency)
  - `Modules/RSTree/Package.swift`
  - `Modules/RSWeb/Package.swift`
  - `Modules/ReadingStats/Package.swift`
  - `Modules/ReadingTime/Package.swift`

---

## 3. Detailed Step-by-Step Implementation

### Step 1: Project Configuration & Deployment Targets
1. In `project.yml`, set `deploymentTarget.iOS: "16.0"`.
2. In `xcconfig/NetNewsWire_project.xcconfig`, set `IPHONEOS_DEPLOYMENT_TARGET = 16.0`.
3. In all 21 `Package.swift` manifests under `Modules/`, change `platforms: [.iOS(.v17)]` to `platforms: [.iOS(.v16)]`.

### Step 2: Tidemark Removal in `RSParser`
Tidemark’s published package specifies `.iOS(.v17)`, blocking SPM resolution at iOS 16.
1. In `Modules/RSParser/Package.swift`:
   - Remove `.package(url: "https://github.com/brentsimmons/Tidemark", from: "1.0.0")`.
   - Remove `"Tidemark"` from target dependencies.
2. In `Modules/RSParser/Sources/RSParser/Feeds/ParsedItem.swift`:
   - Remove `import Tidemark`.
   - Replace Markdown rendering block in initializer with:
     ```swift
     // `markdown` is carried and persisted but not rendered (Tidemark was removed to allow an iOS 16 target).
     self.contentHTML = contentHTML
     ```
3. Copy `Modules/RSParser/Tests/RSParserTests/Feeds/ParsedItemMarkdownTests.swift` from `nectar16`.

### Step 3: Core iOS 16 Compatibility Shims
Copy the three foundational shims into `iOS/`:
1. `iOS/UIKit Extensions/TraitChangeObserving.swift`:
   - Defines `ObservedTrait` (`.userInterfaceStyle`, `.preferredContentSizeCategory`).
   - Adds `observeTraits` on `UIView` and `UIViewController`.
   - Embeds `TraitChangeObserverView` which triggers `traitCollectionDidChange` on iOS 16.
2. `iOS/Shared/EmptyStateView.swift`:
   - Renders `ContentUnavailableView` on iOS 17+.
   - Renders `EmptyStateFallbackView` (vertical stack with icon, title, secondary description) on iOS 16.
3. `iOS/Shared/ViewAvailability.swift`:
   - Adds `@ViewBuilder func scrollClipDisabledIfAvailable() -> some View`.

### Step 4: Trait Change Migration (`registerForTraitChanges` → `observeTraits`)
Replace all call sites of `registerForTraitChanges` with `observeTraits`.

*Special attention to commit `83cc8e51c`*:
- In `iOS/Article/WebViewController.swift`:
  - `viewDidLoad()`: Replace `registerForTraitChanges([UITraitUserInterfaceStyle.self])` with:
    ```swift
    observeTraits([.userInterfaceStyle]) { (self: WebViewController, previousTraitCollection: UITraitCollection) in
        guard self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle else { return }
        self.applyResolvedBackgroundColors()
    }
    ```
- In `iOS/Article/WebViewController+Annotations.swift`:
  - Update comments referencing `registerForTraitChanges` to `observeTraits`.
- In `iOS/Article/ArticleViewController.swift`:
  - In `viewDidLoad()`: Replace `registerForTraitChanges([UITraitUserInterfaceStyle.self])` with `observeTraits([.userInterfaceStyle])`.
- In `iOS/Article/ArticleSearchBar.swift`:
  - In `commonInit()`: Replace `registerForTraitChanges` with `observeTraits([.userInterfaceStyle])`.
- In `iOS/SceneDelegate.swift`:
  - Replace `window!.registerForTraitChanges` with `window!.observeTraits([.userInterfaceStyle])`.
- In `iOS/MainFeed/MainFeedCollectionViewController.swift`:
  - In `viewDidLoad()`:
    ```swift
    observeTraits([.preferredContentSizeCategory]) { (self: MainFeedCollectionViewController, _: UITraitCollection) in
        self.preferredContentSizeCategoryDidChange()
    }
    observeTraits([.userInterfaceStyle]) { (self: MainFeedCollectionViewController, previousTraitCollection: UITraitCollection) in
        guard self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle else { return }
        self.applyListBackground()
        self.applySurfacePaletteNavigationBarAppearance()
    }
    ```
- In `iOS/MainTimeline/MainTimelineModernViewController.swift`:
  - In `viewDidLoad()`: Replace `registerForTraitChanges` with `observeTraits([.userInterfaceStyle])`.
- In `iOS/Settings/SettingsViewController.swift`:
  - In `makeSurfacePaletteAwareHostingController`: Replace `hostingController.registerForTraitChanges` with `hostingController.observeTraits([.userInterfaceStyle])`.
- In `iOS/Settings/SettingsBackgroundPalette.swift`:
  - In `applySettingsBackgroundPalette`: Replace `registerForTraitChanges` with `observeTraits([.userInterfaceStyle])`.
- In `iOS/Settings/SurfacePalettePreviewCell.swift`:
  - In `commonInit()`: Replace `registerForTraitChanges` with `observeTraits([.userInterfaceStyle])`.

### Step 5: Swift Observation Migration (`@Observable` → `ObservableObject`)
iOS 16 does not support the Swift `Observation` framework (`@Observable`, `@ObservationIgnored`). Migrate view models to `ObservableObject` and `Combine`:
1. `Shared/Dinosaurs/DinosaursViewModel.swift`:
   - Replace `@Observable` with `final class DinosaursViewModel: ObservableObject`.
   - Mark `rows`, `showAccountColumn`, and `monthThreshold` with `@Published`.
   - In `iOS/Settings/DinosaursView.swift`: Use `@StateObject private var viewModel = DinosaursViewModel()`.
2. `iOS/Settings/AO3SettingsModel.swift`:
   - Replace `import Observation` with `import Combine`.
   - Replace `@Observable` with `final class AO3SettingsModel: ObservableObject`.
   - Add `@Published` to `isSignedIn`, `sessionEnded`, `rateLimitResumeDate`, `challengeCapturedAt`.
   - Remove `@ObservationIgnored`.
   - In `iOS/Settings/AO3AccountSettingsView.swift`: Use `@ObservedObject var model: AO3SettingsModel` or `@StateObject`.
3. `iOS/Settings/AO3WorksNeedingAttentionViewModel.swift`:
   - Replace `import Observation` with `import Combine`.
   - Conform to `ObservableObject` and add `@Published` to state properties (`articlesNeedingAttention`, `isRefreshing`, etc.).
   - In `iOS/Settings/AO3WorksNeedingAttentionView.swift`: Use `@ObservedObject` or `@StateObject`.

### Step 6: Empty States Migration (`ContentUnavailableView` → `EmptyStateView`)
Replace all 5 `ContentUnavailableView` call sites:
1. `iOS/Account/AccountNotificationInspectorView.swift`:
   ```swift
   EmptyStateView(
       title: Text("Notifications Disabled"),
       systemImage: "bell.slash",
       description: Text("Enable Notifications in Settings", comment: "Enable Notifications in Settings")
   )
   ```
2. `iOS/Article/Annotations/AnnotationsListView.swift`:
   ```swift
   EmptyStateView(
       title: Text(verbatim: NSLocalizedString("No Highlights", comment: "Annotations list empty state title")),
       systemImage: "highlighter",
       description: Text("Select text in a work to highlight it.", comment: "Annotations list empty state message")
   )
   ```
3. `iOS/Settings/AO3WorksNeedingAttentionView.swift`:
   ```swift
   EmptyStateView(
       title: Text(verbatim: NSLocalizedString("No Works Needing Attention", comment: "Empty state title")),
       systemImage: "checkmark.circle"
   )
   ```
4. `iOS/Settings/ActivityLogView.swift`:
   ```swift
   EmptyStateView(
       title: Text(verbatim: NSLocalizedString("No Activity Logged", comment: "Activity log empty state")),
       systemImage: "checkmark.circle"
   )
   ```
5. `iOS/Settings/ErrorLogView.swift`:
   ```swift
   EmptyStateView(
       title: Text(verbatim: NSLocalizedString("No Errors Logged", comment: "Error log empty state")),
       systemImage: "checkmark.circle"
   )
   ```

### Step 7: SwiftUI Modifier & API Adjustments
1. **`.onChange(of:)`**:
   - iOS 17 introduced 0-parameter and 2-parameter (`{ oldValue, newValue in }`) overloads. iOS 16 only supports `.onChange(of: value) { newValue in }`.
   - Migrate call sites in:
     - `iOS/Article/Annotations/AnnotationsListView.swift`
     - `iOS/Article/Annotations/TextReplacementSettingsView.swift`
     - `iOS/Import/AO3LinkListImportView.swift`
     - `iOS/ReadingStats/ReadingHeatmapView.swift`
     - `iOS/ReadingTime/ReadingTimeSettingsView.swift`:
       - Introduce `StrictLimitConfirmation` enum with pure function `needsConfirmation(from:to:)`.
       - In `DailyLimitDetailView`, maintain `@State private var previousMinutes: Int?`, populate in `.onAppear`, and calculate confirmation in `.onChange(of: minutes) { newValue in ... }`.
2. **`scrollClipDisabled()`**:
   - In `iOS/ReadingStats/ReadingHeatmapView.swift`, replace `.scrollClipDisabled()` with `.scrollClipDisabledIfAvailable()`.
3. **`Text` Styling in `AnnotationsListView.swift`**:
   - `editSummary()` concatenates `Text` elements with `+`. On iOS 16, `Text.foregroundStyle` is unavailable. Use `.foregroundColor(.secondary)`, `.foregroundColor(Color(uiColor: .tertiaryLabel))`, and `.foregroundColor(.primary)`.
4. **`AboutCreditView.swift`**:
   - Replace `.foregroundStyle(.link)` with `.foregroundColor(Color(uiColor: .link))`.
5. **Assets / SF Symbols**:
   - In `Shared/Assets.swift`: Change `document.on.document` to `doc.on.doc`.
   - In `iOS/Settings/DinosaurRowView.swift`: Change `.monospaced()` to `.font(.system(.caption, design: .monospaced))`.
6. **`MainFeedCollectionViewFolderCell.swift`**:
   - Replace bare `UIView.animate { }` with:
     ```swift
     UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: []) {
         self.unreadCountLabel.alpha = alpha
     }
     ```

### Step 8: Isolated WebKit Data Store in `AO3AuthenticatedWebViewController`
On iOS 16, `WKWebsiteDataStore(forIdentifier:)` does not exist.
In `iOS/Article/AO3AuthenticatedWebViewController.swift`:
```swift
@MainActor private static let nonPersistentFallbackDataStore = WKWebsiteDataStore.nonPersistent()

@MainActor private static func makeDataStore() -> WKWebsiteDataStore {
    if #available(iOS 17, *) {
        return WKWebsiteDataStore(forIdentifier: dataStoreIdentifier)
    }
    return nonPersistentFallbackDataStore
}
```
Use `Self.makeDataStore()` in `viewDidLoad()` and `clearBrowserData()`.

### Step 9: Xcode Project Integration (`project.pbxproj`)
Update `NetNewsWire.xcodeproj/project.pbxproj`:
1. Add PBXFileReference and PBXBuildFile for:
   - `iOS/UIKit Extensions/TraitChangeObserving.swift`
   - `iOS/Shared/EmptyStateView.swift`
   - `iOS/Shared/ViewAvailability.swift`
   - `Tests/NetNewsWire-iOSTests/DinosaursViewModelObservationTests.swift`
   - `Tests/NetNewsWire-iOSTests/EmptyStateViewTests.swift`
   - `Tests/NetNewsWire-iOSTests/StrictLimitConfirmationTests.swift`
   - `Tests/NetNewsWire-iOSTests/TraitChangeObservingTests.swift`
2. Add files to appropriate PBXGroup:
   - `TraitChangeObserving.swift` -> `UIKit Extensions`
   - `EmptyStateView.swift`, `ViewAvailability.swift` -> `Shared`
   - Test files -> `Tests/NetNewsWire-iOSTests`
3. Remove Tidemark package reference and Framework build file.

### Step 10: Documentation Updates
1. **`CLAUDE.md`**:
   - Add notes to routing and table for `TraitChangeObserving.swift` and `EmptyStateView.swift`.
   - Note minimum deployment target is iOS 16.0.
2. **`docs/module-layout.md`**:
   - Add `Minimum OS` section specifying iOS 16.0 and documenting known degradations.
   - Add `Trait observer helper` section explaining `observeTraits`.
3. **`docs/upstream-drift.md`**:
   - Record removal of Tidemark and addition of iOS 16 compatibility shims under "Deliberate behavior notes" and "Change log".

---

## 4. Verification & Testing Checklist

- [ ] **SPM Build**: Run `swift build` across all packages in `Modules/` to confirm all targets compile cleanly at `.iOS(.v16)`.
- [ ] **Package Test Plan Guard**: Run `./scripts/check-test-plan.sh` to ensure all package test targets are accounted for in `Nectar-CI.xctestplan`.
- [ ] **Unit Tests**: Run `./test.sh` to execute the full test suite (`Nectar-CI`). Ensure the new tests pass:
  - `ParsedItemMarkdownTests`
  - `DinosaursViewModelObservationTests`
  - `EmptyStateViewTests`
  - `StrictLimitConfirmationTests`
  - `TraitChangeObservingTests`
- [ ] **Release Settings Verification**: Verify `xcodebuild -showBuildSettings` outputs `IPHONEOS_DEPLOYMENT_TARGET = 16.0`.
- [ ] **Smoke Test on Simulator**: Launch on available simulator (e.g., iPhone 17 running iOS 18+ or iOS 16 device if connected) and verify:
  - Theme switching and appearance switching trigger `observeTraits` without lag or crashes.
  - Empty states render cleanly in Annotations, Activity Log, and Error Log.
  - AO3 in-app browser opens and logs in.
