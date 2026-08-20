//
//  ToolbarFunctionCell.swift
//  NetNewsWire-iOS
//
//  A plain UISwitch row, one per (ToolbarFunction, ToolbarBar) pair --
//  unifies ArticleToolbarToggleCell and BottomToolbarToggleCell into one
//  type, since both were the same UISwitch-row shape switching over a
//  now-merged case set. Used two ways by ToolbarsCustomizerViewController:
//  as an inline-placement row in the functions section
//  (configure(function:bar:isOn:isEnabled:)), and, indented, as an
//  overflow-membership row in the separate overflow section
//  (configure(overflowFunction:bar:isOn:isEnabled:)) -- see that
//  controller's own header comment for the section layout.
//

import UIKit

final class ToolbarFunctionCell: UICollectionViewListCell {

	static let reuseIdentifier = "ToolbarFunctionCell"

	private let label: UILabel = {
		let label = UILabel()
		label.font = .preferredFont(forTextStyle: .body)
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}()

	private let toggle: UISwitch = {
		let toggle = UISwitch()
		toggle.translatesAutoresizingMaskIntoConstraints = false
		return toggle
	}()

	private var function: ToolbarFunction?
	private var bar: ToolbarBar?
	private var isOverflowRow = false

	private var labelLeadingConstraint: NSLayoutConstraint!
	private static let baseLeading: CGFloat = 16
	private static let indentedLeading: CGFloat = 40

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		contentView.addSubview(label)
		contentView.addSubview(toggle)
		labelLeadingConstraint = label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.baseLeading)
		NSLayoutConstraint.activate([
			labelLeadingConstraint,
			label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
		])
		toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
	}

	/// Inline-placement row: toggling writes through
	/// setToolbarFunctionEnabled(_:on:_:), which also clears this same
	/// function's overflow flag on `bar` (see that method's own doc
	/// comment on the mutual-exclusion invariant). Carries a trailing
	/// .reorder() accessory so ToolbarsCustomizerViewController's
	/// functions-section drag-to-reorder has a handle to grab -- only
	/// the inline row gets one; the overflow-membership row below has no
	/// meaningful order of its own (see that controller's own header
	/// comment on why reorder handles are functions-section-only).
	func configure(function: ToolbarFunction, bar: ToolbarBar, isOn: Bool, isEnabled: Bool = true) {
		self.function = function
		self.bar = bar
		self.isOverflowRow = false
		label.text = function.title
		label.isEnabled = isEnabled
		toggle.isOn = isOn
		toggle.isEnabled = isEnabled
		labelLeadingConstraint.constant = Self.baseLeading
		accessories = [.reorder()]
	}

	/// Overflow-membership row, indented to read as nested under the
	/// bar's overflow-toggle row -- toggling writes through
	/// setToolbarFunctionInOverflow(_:on:_:), which mirrors the
	/// inline-row invariant from the other direction. `isEnabled` mirrors
	/// the inline-configure method's own parameter of the same name
	/// (label.isEnabled/toggle.isEnabled at commonInit()'s target
	/// wiring): the overflow table now always renders these rows (see
	/// ToolbarsCustomizerViewController's own header comment on the
	/// table split), greyed out via this flag rather than removed from
	/// the collection view, whenever the bar's overflow master switch is
	/// off.
	func configure(overflowFunction function: ToolbarFunction, bar: ToolbarBar, isOn: Bool, isEnabled: Bool = true) {
		self.function = function
		self.bar = bar
		self.isOverflowRow = true
		label.text = function.title
		label.isEnabled = isEnabled
		toggle.isOn = isOn
		toggle.isEnabled = isEnabled
		labelLeadingConstraint.constant = Self.indentedLeading
		accessories = []
	}

	@objc private func toggleChanged() {
		guard let function, let bar else { return }
		if isOverflowRow {
			AppDefaults.shared.setToolbarFunctionInOverflow(function, on: bar, toggle.isOn)
		} else {
			AppDefaults.shared.setToolbarFunctionEnabled(function, on: bar, toggle.isOn)
		}
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		var backgroundConfig: UIBackgroundConfiguration
		if #available(iOS 18, *) {
			backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)
		} else {
			backgroundConfig = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
		}
		backgroundConfig.backgroundColor = Assets.Colors.settingsCellBackground(for: traitCollection)
		backgroundConfig.cornerRadius = 20
		self.backgroundConfiguration = backgroundConfig
	}
}
