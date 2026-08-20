//
//  ToolbarsCustomizerViewController.swift
//  NetNewsWire-iOS
//
//  Replaces ArticleToolbarCustomizerViewController (top bar only) and
//  BottomToolbarCustomizerViewController (bottom bar only) with a single
//  screen driven by a UISegmentedControl tab (Top / Bottom), following
//  ToolbarFunction's unification of the two prior per-bar toggle enums
//  -- see docs/settings-screen.md's "Toolbars screen" section for the
//  full rationale.
//
//  Three-section UICollectionViewCompositionalLayout list: Preview (0),
//  Functions (1), Overflow (2). The Functions section holds exactly one
//  ToolbarFunctionCell per ToolbarFunction.allCases, in this bar's
//  persisted display order (AppDefaults.toolbarFunctionOrder(for:)), and
//  supports drag-to-reorder. The Overflow section holds the
//  ToolbarOverflowToggleCell master switch at item 0, followed by one
//  row per function not currently inline on the active bar (or a single
//  ToolbarOverflowEmptyStateCell when that set is empty) -- these rows
//  are always present, not just when the master switch is on; they're
//  greyed out (isEnabled: false) instead of removed when it's off, so
//  the section's shape doesn't change under the person as they flip the
//  switch. Switching the Top/Bottom tab reloads the collection view in
//  place; no animation, since the row counts themselves change (Overflow's
//  candidate set depends on which functions are inline on the active bar).
//
//  Cap: prevNext costs 2 slots (AppDefaults.toolbarFunctionSlotCost(_:)),
//  everything else costs 1, the overflow icon itself costs 1 when that
//  bar's overflow switch is on (it renders alongside inline icons, not
//  instead of them -- see ArticleViewController.toolbarItems(for:overflowItem:)),
//  capped at maxSlots(for:) per bar. Top's cap is 4, one lower than
//  bottom's 5, to leave room for the navigation back button sharing the
//  same UINavigationBar. The cap always applies -- it no longer lifts
//  when overflow is on, since overflow stopped being a full-bar collapse.
//  The Functions section header shows a "used/cap" badge reflecting this.
//  The overflow toggle row itself greys out the same way a Functions row
//  does when turning it on would exceed the cap (it's still off, so it
//  hasn't paid its slot yet, but turning it on would).
//
//  Functions-section drag-to-reorder is UICollectionViewDragDelegate/
//  DropDelegate-driven (+Drag.swift/+Drop.swift), not the older
//  long-press installsStandardGestureForInteractiveMovement system --
//  ToolbarFunctionCell's .reorder() UICellAccessory is a handle for the
//  former, not the latter.
//
//  Both sections reload on the generic UserDefaults.didChangeNotification,
//  same live-update path ArticleViewController.userDefaultsDidChange(_:)
//  already uses to repaint the real bars -- except while a drag-reorder
//  gesture is in progress, when the reload is skipped so the resulting
//  notification from the drag's own write doesn't stomp the live
//  animation (see userDefaultsDidChange()).
//

import UIKit

class ToolbarsCustomizerViewController: UICollectionViewController, SettingsPaletteBackgroundHosting {

	var paletteBackgroundView: UIView { collectionView }

	private var previewSection: Int { 0 }
	// internal, not private: read by +Drag.swift/+Drop.swift to restrict
	// reordering to this section.
	var functionsSection: Int { 1 }
	private var overflowSection: Int { 2 }

	// internal, not private: read by +Drag.swift/+Drop.swift.
	var activeBar: ToolbarBar = .top

	private let segmentedControl: UISegmentedControl = {
		let topTitle = NSLocalizedString("Top", comment: "Toolbars screen: top bar tab")
		let bottomTitle = NSLocalizedString("Bottom", comment: "Toolbars screen: bottom bar tab")
		let control = UISegmentedControl(items: [topTitle, bottomTitle])
		control.selectedSegmentIndex = 0
		control.translatesAutoresizingMaskIntoConstraints = false
		return control
	}()

	override func viewDidLoad() {
		super.viewDidLoad()
		title = NSLocalizedString("Toolbars", comment: "Toolbars screen title")

		// Block-based observers only weakly capture self and are safe to
		// leave registered for the process lifetime -- same rationale as
		// the two prior controllers' own observers (see
		// ArticleToolbarCustomizerViewController's retired header comment).
		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}

		NotificationCenter.default.addObserver(forName: .surfaceTintDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.refreshPaletteCellBackgrounds()
			}
		}

		configureSegmentedControl()
		configureCollectionView()
		configureSettingsPaletteBackground()
		configureResetButton()
	}

	// SettingsPaletteBackgroundHosting
	func refreshPaletteCellBackgrounds() {
		userDefaultsDidChange()
	}

	private func configureSegmentedControl() {
		segmentedControl.addTarget(self, action: #selector(activeBarChanged), for: .valueChanged)
		let header = UIView()
		header.translatesAutoresizingMaskIntoConstraints = false
		header.addSubview(segmentedControl)
		NSLayoutConstraint.activate([
			segmentedControl.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
			segmentedControl.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
			segmentedControl.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
			segmentedControl.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8)
		])
		header.frame = CGRect(x: 0, y: 0, width: 0, height: 56)
		collectionView.contentInset.top = 0
		navigationItem.titleView = nil
		collectionView.backgroundView = nil
		// Fixed, non-scrolling tab strip above the collection view, same
		// approach as other settings screens that pin a control above a
		// UICollectionViewController's own view rather than fighting the
		// compositional layout for a sticky supplementary item.
		view.addSubview(header)
		header.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			header.heightAnchor.constraint(equalToConstant: 56)
		])
		collectionView.contentInset.top = 56
		collectionView.verticalScrollIndicatorInsets.top = 56
	}

	/// Trailing "Reset" button, scoped to whichever bar is active --
	/// matches the one existing reset affordance in Settings
	/// (ArticleThemeListView.resetToThemeDefaults()), which resets
	/// immediately with no confirmation alert. This screen frames
	/// everything per-activeBar already (the Top/Bottom tab), so "reset
	/// the bar I'm looking at" reads as the natural scope for this
	/// button, not both bars at once -- see AppDefaults.resetToolbarDefaults(for:)'s
	/// own doc comment for this same judgment call flagged for product
	/// review, since a toolbar reset loses more (custom order plus
	/// placements) than the theme-color reset this convention is drawn
	/// from.
	private func configureResetButton() {
		let title = NSLocalizedString("Reset", comment: "Toolbars screen: reset active bar to defaults")
		let button = UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(resetTapped))
		button.tintColor = .systemRed
		navigationItem.rightBarButtonItem = button
	}

	@objc private func resetTapped() {
		AppDefaults.shared.resetToolbarDefaults(for: activeBar)
	}

	@objc private func activeBarChanged() {
		activeBar = segmentedControl.selectedSegmentIndex == 0 ? .top : .bottom
		collectionView.reloadData()
	}

	private func configureCollectionView() {
		collectionView.register(
			TimelineHeaderView.self,
			forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
			withReuseIdentifier: TimelineHeaderView.reuseIdentifier
		)

		collectionView.register(ToolbarPreviewCell.self, forCellWithReuseIdentifier: ToolbarPreviewCell.reuseIdentifier)
		collectionView.register(ToolbarFunctionCell.self, forCellWithReuseIdentifier: ToolbarFunctionCell.reuseIdentifier)
		collectionView.register(ToolbarOverflowToggleCell.self, forCellWithReuseIdentifier: ToolbarOverflowToggleCell.reuseIdentifier)
		collectionView.register(ToolbarOverflowEmptyStateCell.self, forCellWithReuseIdentifier: ToolbarOverflowEmptyStateCell.reuseIdentifier)

		var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
		config.showsSeparators = false
		config.headerMode = .supplementary

		let layout = UICollectionViewCompositionalLayout.list(using: config)

		collectionView.setCollectionViewLayout(layout, animated: false)

		// Same-section reordering within the Functions section, driven by
		// ToolbarFunctionCell's .reorder() UICellAccessory. That accessory
		// is a handle for UIKit's drag-and-drop system, not the older
		// long-press-anywhere reordering gesture -- it only starts a drag
		// once a UICollectionViewDragDelegate hands back an item, so
		// dragInteractionEnabled alone (with no drag delegate) never
		// actually begins a drag. See +Drag.swift/+Drop.swift for the
		// delegate pair, same split MainFeedCollectionViewController uses
		// for the sidebar's cross-container drops.
		collectionView.dragInteractionEnabled = true
		collectionView.dragDelegate = self
		collectionView.dropDelegate = self
	}

	// MARK: Row layout

	/// This bar's persisted display order -- same source
	/// ArticleViewController.displayOrder(for:) and
	/// ToolbarPreviewCell.configure(bar:) read, so the reorder handles on
	/// this screen's Functions section reorder the real toolbar and the
	/// live preview for free.
	// internal, not private: read/written by +Drag.swift/+Drop.swift to
	// build the drag item and commit a drop's reorder.
	var functionOrder: [ToolbarFunction] {
		AppDefaults.shared.toolbarFunctionOrder(for: activeBar)
	}

	/// Functions not currently placed inline on `activeBar`, in this
	/// bar's display order -- the candidate set for the Overflow
	/// section's membership rows. Always rendered regardless of the
	/// master switch's state (see ToolbarFunctionCell's isEnabled
	/// parameter); only meaningful for actual overflow placement when
	/// overflowSectionIsShown is also true.
	private var overflowCandidates: [ToolbarFunction] {
		functionOrder.filter { !AppDefaults.shared.isToolbarFunctionEnabled($0, on: activeBar) }
	}

	private var overflowSectionIsShown: Bool {
		AppDefaults.shared.isToolbarOverflowMenuEnabled(on: activeBar)
	}

	// MARK: Icon cap

	/// Inline icon slots this cap applies to (matches
	/// ArticleViewController.toolbarItems(for:)'s fixed-width leading/
	/// trailing cluster on either bar) -- prevNext counts as 2 slots via
	/// AppDefaults.toolbarFunctionSlotCost(_:). Top's cap is one lower
	/// than bottom's to leave room for the navigation back button, which
	/// occupies the bar's leading edge but isn't itself a ToolbarFunction
	/// (it's not part of rightBarButtonItems()'s count, but it does share
	/// the same physical UINavigationBar width). The bottom UIToolbar has
	/// no equivalent fixed-width neighbor, so it gets the full 5.
	private static func maxSlots(for bar: ToolbarBar) -> Int {
		switch bar {
		case .top: return 4
		case .bottom: return 5
		}
	}

	/// Slots currently used on `activeBar`, including the overflow icon
	/// itself when that bar's overflow switch is on -- overflow is now
	/// additive (see ArticleViewController.toolbarItems(for:overflowItem:)),
	/// rendered alongside inline icons rather than replacing them, so it
	/// occupies one slot in the same fixed-width cluster the cap protects,
	/// same as the settings mockup's usedSlots().
	private func slotsUsed(excluding function: ToolbarFunction? = nil) -> Int {
		let overflowCost = overflowSectionIsShown ? 1 : 0
		return overflowCost + ToolbarFunction.allCases
			.filter { $0 != function && AppDefaults.shared.isToolbarFunctionEnabled($0, on: activeBar) }
			.reduce(0) { $0 + AppDefaults.toolbarFunctionSlotCost($1) }
	}

	// MARK: UICollectionViewDataSource

	override func numberOfSections(in collectionView: UICollectionView) -> Int {
		return 3
	}

	override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		switch section {
		case previewSection:
			return 1
		case functionsSection:
			// One row per ToolbarFunction, no master-switch row here --
			// the overflow toggle moved to the Overflow section (item 0
			// there). No -1 index offset needed at this section's cell
			// lookup, unlike the pre-split single-table layout.
			return ToolbarFunction.allCases.count
		case overflowSection:
			// Overflow section: 1 (the master switch) + either
			// overflowCandidates.count membership rows, or, when that's
			// empty (every function already inline on this bar), a
			// single ToolbarOverflowEmptyStateCell -- always rendered,
			// not conditioned on the master switch's own state.
			return 1 + max(overflowCandidates.count, 1)
		default:
			return 0
		}
	}

	override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		if indexPath.section == previewSection {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ToolbarPreviewCell.reuseIdentifier, for: indexPath) as! ToolbarPreviewCell
			cell.configure(bar: activeBar)
			return cell
		}

		if indexPath.section == functionsSection {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ToolbarFunctionCell.reuseIdentifier, for: indexPath) as! ToolbarFunctionCell
			let function = functionOrder[indexPath.item]
			let isOn = AppDefaults.shared.isToolbarFunctionEnabled(function, on: activeBar)
			// A row already on stays interactive (so it can be turned back
			// off); an off row past the cap becomes non-interactive,
			// disabled -- same shape as the pre-unification controllers.
			// Forward-only: existing over-cap configurations aren't
			// trimmed, they just can't add further icons. The cap always
			// applies, overflow-on or not -- overflow is additive (occupies
			// one slot alongside inline icons), not a full-bar mode switch,
			// so there's no longer a state where the fixed-width cluster
			// has no cap to run out of room in.
			let wouldAdd = AppDefaults.toolbarFunctionSlotCost(function)
			let capReached = !isOn
				&& (slotsUsed(excluding: function) + wouldAdd > Self.maxSlots(for: activeBar))
			cell.configure(function: function, bar: activeBar, isOn: isOn, isEnabled: !capReached)
			return cell
		}

		// Overflow section.
		if indexPath.item == 0 {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ToolbarOverflowToggleCell.reuseIdentifier, for: indexPath) as! ToolbarOverflowToggleCell
			// The overflow icon itself costs 1 slot once its switch is on
			// (see slotsUsed(excluding:)'s overflowCost) -- if it's
			// currently off, turning it on needs to fit in that same cap,
			// same as any ToolbarFunction row below. Already-on stays
			// interactive so it can be turned back off, matching the
			// function rows' capReached rule.
			let overflowCapReached = !overflowSectionIsShown
				&& (slotsUsed() + 1 > Self.maxSlots(for: activeBar))
			cell.configure(bar: activeBar, isOn: overflowSectionIsShown, isEnabled: !overflowCapReached)
			return cell
		}

		let candidates = overflowCandidates
		if candidates.isEmpty {
			return collectionView.dequeueReusableCell(withReuseIdentifier: ToolbarOverflowEmptyStateCell.reuseIdentifier, for: indexPath) as! ToolbarOverflowEmptyStateCell
		}

		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ToolbarFunctionCell.reuseIdentifier, for: indexPath) as! ToolbarFunctionCell
		let function = candidates[indexPath.item - 1]
		let isOn = AppDefaults.shared.isToolbarFunctionInOverflow(function, on: activeBar)
		cell.configure(overflowFunction: function, bar: activeBar, isOn: isOn, isEnabled: overflowSectionIsShown)
		return cell
	}

	// MARK: UICollectionViewDelegate

	// Reordering itself (starting a drag, committing a drop) lives in
	// +Drag.swift/+Drop.swift -- canMoveItemAt/moveItemAt were removed
	// from here because they belong to the older long-press
	// installsStandardGestureForInteractiveMovement system, which
	// dragInteractionEnabled's drag-and-drop system supersedes rather
	// than composes with; left in place they were simply never called.

	override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
		guard kind == UICollectionView.elementKindSectionHeader else {
			return UICollectionReusableView()
		}

		let header = collectionView.dequeueReusableSupplementaryView(
			ofKind: kind,
			withReuseIdentifier: TimelineHeaderView.reuseIdentifier,
			for: indexPath
		) as! TimelineHeaderView

		switch indexPath.section {
		case previewSection:
			header.label.text = NSLocalizedString("Preview", comment: "Preview")
		case functionsSection:
			header.label.text = NSLocalizedString("Which Functions Appear", comment: "Toolbars screen: functions section header")
			let used = slotsUsed()
			let cap = Self.maxSlots(for: activeBar)
			header.detailLabel.text = "\(used)/\(cap)"
			header.detailLabel.textColor = used > cap ? .systemRed : .secondaryLabel
			header.detailLabel.isHidden = false
		case overflowSection:
			header.label.text = NSLocalizedString("Overflow Menu", comment: "Toolbars screen: overflow section header")
		default:
			header.label.text = ""
		}
		return header
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
		CGSize(width: collectionView.bounds.width, height: 50)
	}

	// No shouldSelectItemAt/didSelectItemAt override needed: neither the
	// preview row, the overflow-toggle row, nor the function rows respond
	// to a tap on the row itself -- each cell's own UISwitch valueChanged
	// target writes back to AppDefaults directly.

	// MARK: Notifications

	func userDefaultsDidChange() {
		// A drag-reorder's own write to AppDefaults posts this same
		// generic notification (see setToolbarFunctionOrder(_:for:) ->
		// UserDefaults.didChangeNotification), which would otherwise
		// trigger a full reloadData() mid-drag-animation and stomp the
		// live reorder gesture -- skip the reload while a drag/drop is
		// in flight; the collection view already has the visually
		// correct order from the interactive move, and the next
		// non-drag-triggered notification (or the drag's own completion)
		// picks up any other state that changed.
		guard !collectionView.hasActiveDrag, !collectionView.hasActiveDrop else { return }
		collectionView.reloadData()
	}

}
