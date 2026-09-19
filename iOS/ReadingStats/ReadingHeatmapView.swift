//
//  ReadingHeatmapView.swift
//  Nectar
//
//  Year-long, week-aligned activity heatmap for Reading Stats' Streaks
//  section. Ported from Aidoku (https://github.com/Aidoku/Aidoku)'s
//  `Aidoku/Features/Settings/Insights/HeatmapView.swift`, Copyright (c)
//  the Aidoku authors (that file's header credits Skitty), licensed under
//  GPL-3.0 (see the LICENSE file at the root of that repository). This
//  file is therefore itself GPL-3.0-licensed -- see THIRD-PARTY-NOTICES.md
//  for the full notice.
//
//  Adapted for this app's `ReadingHeatmapData` (see
//  ReadingStatsCalendar.swift, also carrying its own Aidoku attribution)
//  in place of Aidoku's `HeatmapData`. Layout, sizes, month-header logic
//  and quantile bucketing are unchanged. Differences:
//   - Aidoku's `centerScrollAnchorPlease()` helper (not present in this
//     app) is inlined below as an iOS 18 `defaultScrollAnchor` gate;
//     `scrollClipDisabled()` is called directly since this app's
//     deployment target is 17.0.
//   - `onChange(of:)` uses the two-parameter form (the one-parameter
//     form Aidoku uses is deprecated as of iOS 17).
//   - Cell accessibility labels use a formatted date and say "words";
//     Aidoku's interpolates the raw `Date`/value.
//

import Account
import SwiftUI

struct ReadingHeatmapView: View {
	let data: ReadingHeatmapData

	private let weekCount: Int
	private let colorForValue: (Int) -> Color
	private let calendar = Calendar.current
	private let monthHeaders: [(index: Int, label: String)]

	private let cellSize: CGFloat = 16
	private let cellSpacing: CGFloat = 2
	private let headerHeight: CGFloat = 16
	private let headerSpacing: CGFloat = 4
	private let sidebarWidth: CGFloat = 32

	init(data: ReadingHeatmapData, themeColor: Color? = nil) {
		self.data = data
		self.weekCount = (data.values.count + 6) / 7 // round result up instead of truncating

		// do "quantile bucketing" to determine heatmap colors
		let themeColor = themeColor ?? .accentColor
		let noColor = Color(uiColor: UIColor { traitCollection in
			if traitCollection.userInterfaceStyle == .dark {
				return UIColor.tertiarySystemGroupedBackground
			} else {
				return UIColor.systemGray6
			}
		})
		self.colorForValue = Self.makeColorMapper(
			values: data.values,
			themeColor: themeColor,
			noColor: noColor
		)

		var result: [(Int, String)] = []
		var lastMonth: Int?
		let calendar = Calendar.current
		let formatter = DateFormatter()
		formatter.dateFormat = "MMM"
		for i in 0..<weekCount {
			let offset = i * 7
			let firstDay = calendar.date(byAdding: .day, value: offset, to: data.startDate)!
			let month = calendar.component(.month, from: firstDay)
			if month != lastMonth {
				// if two month headers are right next to each other, remove the first one
				if !result.isEmpty && i == result[result.count - 1].0 + 1 {
					result.removeLast()
				}
				result.append((i, formatter.string(from: firstDay)))
				lastMonth = month
			}
		}
		self.monthHeaders = result
	}

	var body: some View {
		ScrollViewReader { proxy in
			let height = 7 * (cellSize + cellSpacing) + headerHeight + headerSpacing * 2
			ScrollView(.horizontal, showsIndicators: false) {
				let topPadding = headerHeight + headerSpacing
				let leadingPadding: CGFloat = sidebarWidth

				ZStack(alignment: .topLeading) {
					// days of week labels
					let daysOfWeek = calendar.shortStandaloneWeekdaySymbols
					let startIndex = calendar.firstWeekday - 1
					ForEach(daysOfWeek.indices, id: \.self) { index in
						Text(daysOfWeek[(index + startIndex) % daysOfWeek.count])
							.font(.system(.caption2, design: .rounded).weight(.medium))
							.foregroundColor(.primary)
							.offset(y: topPadding + CGFloat(index) * (cellSize + cellSpacing))
							.frame(height: cellSize)
					}

					// month headers
					ForEach(monthHeaders, id: \.index) { header in
						Text(header.label)
							.font(.system(.caption2, design: .rounded).weight(.medium))
							.foregroundColor(.primary)
							.fixedSize(horizontal: true, vertical: false)
							.frame(height: headerHeight, alignment: .leading)
							.offset(x: leadingPadding + CGFloat(header.index) * (cellSize + cellSpacing))
					}

					// heatmap cells
					HStack(alignment: .top, spacing: cellSpacing) {
						ForEach(0..<weekCount, id: \.self) { weekIndex in
							VStack(spacing: cellSpacing) {
								ForEach(0..<7, id: \.self) { dayIndex in
									let offset = weekIndex * 7 + dayIndex
									if data.values.indices.contains(offset) {
										let value = data.values[offset]
										let date = calendar.date(byAdding: .day, value: offset, to: data.startDate)!
										Rectangle()
											.fill(colorForValue(value))
											.frame(width: cellSize, height: cellSize)
											.cornerRadius(3)
											.overlay(
												RoundedRectangle(cornerRadius: 3)
													.stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
											)
											.accessibilityLabel(Text("\(date.formatted(date: .abbreviated, time: .omitted)): \(value) words"))
									}
								}
							}
							.id(weekIndex == weekCount - 1 ? "lastWeek" : nil)
						}
					}
					.padding(.top, topPadding)
					.padding(.leading, leadingPadding)
				}
				.frame(
					width: leadingPadding + CGFloat(weekCount) * (cellSize + cellSpacing),
					height: height
				)
			}
			.frame(height: height)
			.onAppear {
				proxy.scrollTo("lastWeek")
			}
			.onChange(of: data) { _, _ in
				proxy.scrollTo("lastWeek", anchor: .trailing)
			}
		}
		.centeredScrollAnchor()
		.scrollClipDisabled()
	}

	// do "quantile bucketing" to determine heatmap colors
	private static func makeColorMapper(
		values: [Int],
		themeColor: Color,
		noColor: Color
	) -> (Int) -> Color {
		let colors = [
			themeColor.opacity(0.3),
			themeColor.opacity(0.4),
			themeColor.opacity(0.55),
			themeColor.opacity(0.75),
			themeColor
		]

		let nonZero = values.filter { $0 > 0 }.sorted()
		guard !nonZero.isEmpty else { return { _ in noColor } }

		func percentile(_ p: Double, in values: [Int]) -> Int {
			let index = Int((Double(values.count - 1) * p).rounded(.down))
			return values[max(0, min(index, values.count - 1))]
		}

		let cap = percentile(0.95, in: nonZero)
		let clipped = nonZero.map { min($0, cap) }

		let thresholds = [
			percentile(0.3, in: clipped),
			percentile(0.4, in: clipped),
			percentile(0.6, in: clipped),
			percentile(0.8, in: clipped),
			percentile(1, in: clipped)
		]

		return { value in
			guard value > 0 else { return noColor }
			let clippedValue = min(value, cap)
			let bucket = thresholds.firstIndex { clippedValue <= $0 } ?? (colors.count - 1)
			return colors[bucket]
		}
	}
}

private extension View {
	@ViewBuilder
	func centeredScrollAnchor() -> some View {
		if #available(iOS 18.0, *) {
			defaultScrollAnchor(.center, for: .alignment)
		} else {
			self
		}
	}
}

#Preview {
	let (totalDays, startDate) = ReadingHeatmapData.daysAndStartDate(asOf: Date(), calendar: .current)
	let values = (0..<totalDays).map { $0 % 4 == 0 ? 0 : ($0 * 37) % 9_000 }
	return ReadingHeatmapView(data: ReadingHeatmapData(startDate: startDate, values: values), themeColor: .green)
		.padding()
}
