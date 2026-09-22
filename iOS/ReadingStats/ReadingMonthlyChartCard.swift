//
//  ReadingMonthlyChartCard.swift
//  Nectar
//
//  Words-per-month card (big total, month-of-year bar chart, tap-to-
//  expand year pills) for Reading Stats' Monthly section. Ported from the
//  monthly-chart card and `YearSelectorView` of Aidoku
//  (https://github.com/Aidoku/Aidoku)'s
//  `Aidoku/Features/Settings/Insights/StatsGridView.swift`, Copyright (c)
//  the Aidoku authors (that file's header credits Skitty), licensed under
//  GPL-3.0 (see the LICENSE file at the root of that repository). This
//  file is therefore itself GPL-3.0-licensed -- see THIRD-PARTY-NOTICES.md
//  for the full notice.
//
//  Extracted from Aidoku's stats grid: the small stat squares, the
//  landscape (always-expanded) layout, and the `GeometryReader`/height
//  binding that existed only to size the grid are dropped, since this
//  card sits alone in a List row. Sizes, fonts and the expand/year-pill
//  behavior are unchanged. `selectedChartData` falls back to an empty
//  month set instead of force-unwrapping, since the selected year can
//  disappear when stats are reset.
//

import Account
import ReadingStats
import SwiftUI

struct ReadingMonthlyChartCard: View {
	let chartData: [ReadingYearlyMonthData]

	@State private var isExpanded = false
	@State private var selectedChartYear: Int? // nil is all-time

	static let chartHeight: CGFloat = 109
	static let chartExpansionHeight: CGFloat = 50

	private var chartCanExpand: Bool {
		chartData.count > 1
	}

	private var chartIsExpanded: Bool {
		isExpanded && chartCanExpand
	}

	private var selectedChartData: ReadingMonthData {
		if let selectedChartYear {
			return chartData.first(where: { $0.year == selectedChartYear })?.data ?? ReadingMonthData()
		} else {
			// combine all chart data
			var total = ReadingMonthData()
			for yearlyData in chartData {
				total += yearlyData.data
			}
			return total
		}
	}

	var body: some View {
		let defaultChartHeight = Self.chartHeight + (chartIsExpanded ? Self.chartExpansionHeight : 0)
		ReadingInsightPlatterView {
			VStack(spacing: 4) {
				HStack {
					VStack(alignment: .leading, spacing: -8) {
						let total = selectedChartData.total
						Text(total, format: .number.notation(.compactName))
							.contentTransition(.numericText())
							.font(.system(size: 64).weight(.bold))
							.minimumScaleFactor(0.5)
						Text(total == 1 ? "word" : "words")
							.font(.system(size: 17).weight(.semibold))
							.padding(.bottom, 5)
					}
					.frame(width: 120, alignment: .leading)

					ReadingYearlyMonthChartView(data: selectedChartData)
						.padding(.vertical, 2)
				}
				.padding(12)
				.frame(height: Self.chartHeight)

				if chartIsExpanded {
					ScrollView(.horizontal) {
						HStack(spacing: 2) {
							YearSelectorView(selectedYear: $selectedChartYear)
							ForEach(chartData, id: \.year) { yearlyData in
								YearSelectorView(year: yearlyData.year, selectedYear: $selectedChartYear)
							}
						}
					}
					.padding(.horizontal)
					.scrollClipDisabled()
				}
			}
			.frame(
				height: defaultChartHeight,
				alignment: .top
			)
			.frame(maxWidth: .infinity)
		}
		.onTapGesture {
			guard chartCanExpand else { return }
			withAnimation {
				isExpanded.toggle()
			}
		}
	}

	struct YearSelectorView: View {
		var year: Int?
		@Binding var selectedYear: Int?

		private var title: String {
			if let year {
				String(format: "%i", year)
			} else {
				String(localized: "All time")
			}
		}

		private var selected: Bool {
			selectedYear == year
		}

		var body: some View {
			VStack {
				Button(title) {
					withAnimation {
						selectedYear = year
					}
				}
				.font(.callout)
			}
			.padding(.vertical, 6)
			.padding(.horizontal, 12)
			.background(RoundedRectangle(cornerRadius: 100).fill(selected ? Color(uiColor: .secondarySystemFill) : .clear))
			.foregroundStyle(selected ? .primary : .secondary)
		}
	}
}

#Preview {
	var recent = ReadingMonthData()
	recent.may = 8_000
	recent.september = 9_500
	var older = ReadingMonthData()
	older.november = 12_000
	return ReadingMonthlyChartCard(chartData: [
		ReadingYearlyMonthData(year: 2025, data: older),
		ReadingYearlyMonthData(year: 2026, data: recent)
	])
	.padding()
}
