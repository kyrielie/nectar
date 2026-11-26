//
//  ToolbarsSettingsView.swift
//  NetNewsWire-iOS
//
//  SwiftUI replacement for `ToolbarsCustomizerViewController`: pure SwiftUI
//  bar preview (avoiding UIKit UINavigationBar/UIToolbar observation loops),
//  grouped On Bar / In Overflow / Available sections, leading SF Symbol icons,
//  live slot usage counter, and drag-to-reorder.
//

import SwiftUI
import UIKit

@MainActor final class ToolbarsSettingsModel: ObservableObject {

	enum Placement: String, CaseIterable, Identifiable {
		case bar
		case overflow
		case off

		var id: String { rawValue }

		var title: String {
			switch self {
			case .bar: return NSLocalizedString("Bar", comment: "Toolbar placement: inline on bar")
			case .overflow: return NSLocalizedString("Overflow", comment: "Toolbar placement: inside overflow menu")
			case .off: return NSLocalizedString("Off", comment: "Toolbar placement: hidden")
			}
		}
	}

	@Published var activeBar: ToolbarBar = .top {
		didSet {
			guard oldValue != activeBar else { return }
			reload()
		}
	}

	@Published private(set) var orderedFunctions: [ToolbarFunction] = []
	@Published private(set) var barFunctions: [ToolbarFunction] = []
	@Published private(set) var overflowFunctions: [ToolbarFunction] = []
	@Published private(set) var offFunctions: [ToolbarFunction] = []
	@Published private(set) var overflowMenuEnabled: Bool = false

	nonisolated(unsafe) private var observer: NSObjectProtocol?

	init(notificationCenter: NotificationCenter = .default) {
		reload()
		observer = notificationCenter.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.reload()
			}
		}
	}

	deinit {
		if let observer {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	var maxSlots: Int {
		activeBar == .top ? 4 : 5
	}

	var slotsUsed: Int {
		let inlineSlots = barFunctions.reduce(0) { $0 + AppDefaults.toolbarFunctionSlotCost($1) }
		let overflowCost = overflowMenuEnabled ? 1 : 0
		return inlineSlots + overflowCost
	}

	var canEnableOverflowMenu: Bool {
		overflowMenuEnabled || slotsUsed + 1 <= maxSlots
	}

	var hasOverflowItems: Bool {
		overflowMenuEnabled && !overflowFunctions.isEmpty
	}

	func canPlaceOnBar(_ function: ToolbarFunction) -> Bool {
		if barFunctions.contains(function) {
			return true
		}
		return slotsUsed + AppDefaults.toolbarFunctionSlotCost(function) <= maxSlots
	}

	func placement(for function: ToolbarFunction) -> Placement {
		if barFunctions.contains(function) {
			return .bar
		}
		if overflowFunctions.contains(function) {
			return .overflow
		}
		return .off
	}

	func setPlacement(_ placement: Placement, for function: ToolbarFunction) {
		let defaults = AppDefaults.shared
		switch placement {
		case .bar:
			guard canPlaceOnBar(function) else { return }
			defaults.setToolbarFunctionEnabled(function, on: activeBar, true)
		case .overflow:
			guard overflowMenuEnabled else { return }
			defaults.setToolbarFunctionInOverflow(function, on: activeBar, true)
		case .off:
			defaults.setToolbarFunctionEnabled(function, on: activeBar, false)
			defaults.setToolbarFunctionInOverflow(function, on: activeBar, false)
		}
		reload()
	}

	func setOverflowMenuEnabled(_ enabled: Bool) {
		guard !enabled || canEnableOverflowMenu else { return }
		AppDefaults.shared.setToolbarOverflowMenuEnabled(on: activeBar, enabled)
		reload()
	}

	func moveBarFunctions(from source: IndexSet, to destination: Int) {
		moveSubset(barFunctions, from: source, to: destination)
	}

	func moveOverflowFunctions(from source: IndexSet, to destination: Int) {
		moveSubset(overflowFunctions, from: source, to: destination)
	}

	private func moveSubset(_ subset: [ToolbarFunction], from source: IndexSet, to destination: Int) {
		var reorderedSubset = subset
		reorderedSubset.move(fromOffsets: source, toOffset: destination)
		let subsetSet = Set(subset)
		var subsetIterator = reorderedSubset.makeIterator()
		let updatedOrder = orderedFunctions.map { item -> ToolbarFunction in
			guard subsetSet.contains(item), let replacement = subsetIterator.next() else {
				return item
			}
			return replacement
		}
		AppDefaults.shared.setToolbarFunctionOrder(updatedOrder, for: activeBar)
		reload()
	}

	func resetActiveBar() {
		AppDefaults.shared.resetToolbarDefaults(for: activeBar)
		reload()
	}

	func reload() {
		let defaults = AppDefaults.shared
		let latestOrder = defaults.toolbarFunctionOrder(for: activeBar)
		let latestOverflow = defaults.isToolbarOverflowMenuEnabled(on: activeBar)
		let latestBar = latestOrder.filter { defaults.isToolbarFunctionEnabled($0, on: activeBar) }
		let latestInOverflow = latestOverflow
			? latestOrder.filter { !defaults.isToolbarFunctionEnabled($0, on: activeBar) && defaults.isToolbarFunctionInOverflow($0, on: activeBar) }
			: []
		let latestOff = latestOrder.filter { function in
			!defaults.isToolbarFunctionEnabled(function, on: activeBar) &&
			(!latestOverflow || !defaults.isToolbarFunctionInOverflow(function, on: activeBar))
		}
		if orderedFunctions != latestOrder { orderedFunctions = latestOrder }
		if overflowMenuEnabled != latestOverflow { overflowMenuEnabled = latestOverflow }
		if barFunctions != latestBar { barFunctions = latestBar }
		if overflowFunctions != latestInOverflow { overflowFunctions = latestInOverflow }
		if offFunctions != latestOff { offFunctions = latestOff }
	}
}

struct ToolbarsSettingsView: View {

	@StateObject private var model = ToolbarsSettingsModel()
	@Environment(\.surfacePaletteObserver) private var surfaceObserver
	@State private var isResetAlertPresented = false

	private var cellBackground: Color {
		surfaceObserver?.settingsCellBackground ?? Color(uiColor: .secondarySystemGroupedBackground)
	}

	var body: some View {
		Form {
			Group {
				barPickerSection
				previewSection
				overflowToggleSection
				onBarSection
				if model.overflowMenuEnabled {
					inOverflowSection
				}
				if !model.offFunctions.isEmpty {
					availableSection
				}
			}
			.listRowBackground(cellBackground)
		}
		.surfacePaletteListBackground()
		.environment(\.editMode, .constant(.active))
		.navigationTitle(NSLocalizedString("Toolbars", comment: "Toolbars screen title"))
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button(NSLocalizedString("Reset", comment: "Toolbars screen: reset active bar to defaults")) {
					isResetAlertPresented = true
				}
			}
		}
		.alert(
			NSLocalizedString("Reset Toolbar?", comment: "Reset toolbar confirmation"),
			isPresented: $isResetAlertPresented
		) {
			Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
			Button(NSLocalizedString("Reset", comment: "Reset button"), role: .destructive) {
				model.resetActiveBar()
			}
		} message: {
			Text(NSLocalizedString("This will restore the default buttons and order for this bar.", comment: "Reset toolbar confirmation message"))
		}
	}

	private var barPickerSection: some View {
		Section {
			Picker(NSLocalizedString("Bar", comment: "Toolbar bar picker"), selection: $model.activeBar) {
				Text(NSLocalizedString("Top", comment: "Toolbars screen: top bar tab")).tag(ToolbarBar.top)
				Text(NSLocalizedString("Bottom", comment: "Toolbars screen: bottom bar tab")).tag(ToolbarBar.bottom)
			}
			.pickerStyle(.segmented)
			.labelsHidden()
		}
		.listRowBackground(Color.clear)
		.listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
	}

	private var previewSection: some View {
		Section {
			ToolbarPreviewView(
				activeBar: model.activeBar,
				barFunctions: model.barFunctions,
				hasOverflowItems: model.hasOverflowItems
			)
			.listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
		} header: {
			Text(NSLocalizedString("Preview", comment: "Toolbars preview header"))
		}
	}

	private var overflowToggleSection: some View {
		Section {
			Toggle(
				NSLocalizedString("Show Overflow Menu", comment: "Toolbars: overflow menu master toggle"),
				isOn: Binding(
					get: { model.overflowMenuEnabled },
					set: { model.setOverflowMenuEnabled($0) }
				)
			)
			.disabled(!model.canEnableOverflowMenu)
		} footer: {
			Text("Reserves 1 bar slot for the ⌘ menu when enabled. Placing Overflow actions requires this menu.", comment: "Toolbars overflow toggle footer")
		}
	}

	private var onBarSection: some View {
		Section {
			if model.barFunctions.isEmpty {
				Text(NSLocalizedString("No buttons on this bar.", comment: "Toolbars empty bar state"))
					.foregroundStyle(.secondary)
					.moveDisabled(true)
			} else {
				ForEach(model.barFunctions, id: \.self) { function in
					ToolbarFunctionRow(function: function, model: model)
				}
				.onMove { source, destination in
					model.moveBarFunctions(from: source, to: destination)
				}
			}
		} header: {
			Text(String(format: NSLocalizedString("On Bar (%d of %d slots)", comment: "Toolbars on-bar header with slot count"), model.slotsUsed, model.maxSlots))
		} footer: {
			Text("Drag to reorder buttons on the bar. Previous & Next Work uses 2 slots.", comment: "Toolbars on-bar footer")
		}
	}

	private var inOverflowSection: some View {
		Section {
			if model.overflowFunctions.isEmpty {
				Text(NSLocalizedString("No buttons in the overflow menu.", comment: "Toolbars empty overflow state"))
					.foregroundStyle(.secondary)
					.moveDisabled(true)
			} else {
				ForEach(model.overflowFunctions, id: \.self) { function in
					ToolbarFunctionRow(function: function, model: model)
				}
				.onMove { source, destination in
					model.moveOverflowFunctions(from: source, to: destination)
				}
			}
		} header: {
			Text(NSLocalizedString("In Overflow Menu", comment: "Toolbars overflow section header"))
		}
	}

	private var availableSection: some View {
		Section {
			ForEach(model.offFunctions, id: \.self) { function in
				ToolbarFunctionRow(function: function, model: model)
					.moveDisabled(true)
			}
		} header: {
			Text(NSLocalizedString("Available", comment: "Toolbars available/off section header"))
		}
	}
}

private struct ToolbarFunctionRow: View {
	let function: ToolbarFunction
	@ObservedObject var model: ToolbarsSettingsModel

	private var slotCost: Int {
		AppDefaults.toolbarFunctionSlotCost(function)
	}

	var body: some View {
		HStack(spacing: 12) {
			if let uiImage = function.icon {
				Image(uiImage: uiImage)
					.renderingMode(.template)
					.foregroundStyle(Color.accentColor)
					.frame(width: 24, alignment: .center)
			}

			VStack(alignment: .leading, spacing: 2) {
				Text(function.title)
					.foregroundStyle(.primary)
				if slotCost > 1 {
					Text(String(format: NSLocalizedString("%d slots", comment: "Toolbar button slot cost"), slotCost))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			Spacer(minLength: 8)

			Menu {
				Button {
					model.setPlacement(.bar, for: function)
				} label: {
					Label(ToolbarsSettingsModel.Placement.bar.title, systemImage: model.placement(for: function) == .bar ? "checkmark" : "")
				}
				.disabled(!model.canPlaceOnBar(function))

				if model.overflowMenuEnabled {
					Button {
						model.setPlacement(.overflow, for: function)
					} label: {
						Label(ToolbarsSettingsModel.Placement.overflow.title, systemImage: model.placement(for: function) == .overflow ? "checkmark" : "")
					}
				}

				Button {
					model.setPlacement(.off, for: function)
				} label: {
					Label(ToolbarsSettingsModel.Placement.off.title, systemImage: model.placement(for: function) == .off ? "checkmark" : "")
				}
			} label: {
				HStack(spacing: 4) {
					Text(model.placement(for: function).title)
					Image(systemName: "chevron.up.chevron.down")
						.font(.caption2)
				}
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.padding(.horizontal, 10)
				.padding(.vertical, 5)
				.background(Color(uiColor: .tertiarySystemFill), in: Capsule())
			}
		}
	}
}

private struct ToolbarPreviewView: View {
	let activeBar: ToolbarBar
	let barFunctions: [ToolbarFunction]
	let hasOverflowItems: Bool

	private var previewIcons: [UIImage] {
		var icons = [UIImage]()
		for function in barFunctions {
			if function == .prevNext {
				if activeBar == .top {
					icons.append(Assets.Images.nextArticle)
					icons.append(Assets.Images.prevArticle)
				} else {
					icons.append(Assets.Images.prevArticle)
					icons.append(Assets.Images.nextArticle)
				}
			} else if let icon = function.icon {
				icons.append(icon)
			}
		}
		if hasOverflowItems {
			switch activeBar {
			case .top:
				icons.insert(Assets.Images.command, at: 0)
			case .bottom:
				icons.append(Assets.Images.command)
			}
		}
		return icons
	}

	var body: some View {
		let icons = previewIcons
		Group {
			if icons.isEmpty {
				Text(NSLocalizedString("Empty bar", comment: "Toolbar preview empty state"))
					.font(.footnote)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .center)
			} else if activeBar == .top {
				HStack(spacing: 18) {
					Spacer(minLength: 0)
					ForEach(Array(icons.enumerated()), id: \.offset) { _, image in
						previewIcon(image)
					}
				}
			} else {
				HStack(spacing: 0) {
					ForEach(Array(icons.enumerated()), id: \.offset) { index, image in
						if index > 0 {
							Spacer(minLength: 8)
						}
						previewIcon(image)
					}
				}
			}
		}
		.frame(height: 44)
		.padding(.horizontal, 16)
		.background(
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.fill(Color(uiColor: .tertiarySystemFill))
		)
		.overlay(
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
		)
	}

	private func previewIcon(_ image: UIImage) -> some View {
		Image(uiImage: image)
			.renderingMode(.template)
			.resizable()
			.scaledToFit()
			.frame(width: 20, height: 20)
			.foregroundStyle(Color.accentColor)
	}
}
