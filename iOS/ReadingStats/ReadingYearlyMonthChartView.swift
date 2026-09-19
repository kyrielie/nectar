//
//  ReadingYearlyMonthChartView.swift
//  Nectar
//
//  Month-of-year bar chart for Reading Stats' Monthly section. Ported from
//  Aidoku (https://github.com/Aidoku/Aidoku)'s
//  `Aidoku/Features/Settings/Insights/YearlyMonthChartView.swift`,
//  Copyright (c) the Aidoku authors, licensed under GPL-3.0
//  (https://github.com/Aidoku/Aidoku#GPL-3.0-1-ov-file). This file is
//  therefore itself GPL-3.0-licensed -- see THIRD-PARTY-NOTICES.md for the
//  full notice.
//
//  Adapted for this app's `ReadingMonth`/`ReadingMonthData` (see
//  ReadingStatsCalendar.swift, also carrying its own Aidoku attribution)
//  in place of Aidoku's `Month`/`MonthData`; bar heights are words read
//  that month rather than chapters completed. The `#available(iOS 16.0, *)`
//  gate Aidoku needs (Swift Charts requires iOS 16+) is dropped since this
//  app's deployment target is 17.0. Bar width (2) and the `#available(iOS
//  27.0, *)` axis-label offset are kept as in Aidoku; the offset is
//  Aidoku's own workaround and has not been verified against this app.
//  `ReadingMonth`'s `Identifiable` conformance lives in Account, next to
//  the type, rather than here.
//

import Account
import Charts
import SwiftUI

extension ReadingMonth {
	var axisLabel: String {
		let locale = Locale.current
		let formatter = DateFormatter()
		formatter.locale = locale
		let monthSymbols = formatter.shortMonthSymbols ?? formatter.monthSymbols ?? []
		let label = monthSymbols[rawValue - 1]

		// use full label for cjk
		if let languageCode = locale.language.languageCode?.identifier, ["ja", "zh", "ko"].contains(languageCode) {
			let fullMonthSymbols = formatter.monthSymbols ?? []
			return fullMonthSymbols[rawValue - 1]
		}

		// otherwise use first letter
		return String(label.prefix(1))
	}
}

struct ReadingYearlyMonthChartView: View {
	let data: ReadingMonthData

	private let maxY: Int

	init(data: ReadingMonthData) {
		self.data = data
		self.maxY = max(data.maxValue, 10) // at least 10
	}

	var body: some View {
		Chart {
			ForEach(ReadingMonth.allCases) { month in
				let value = data.value(for: month)
				// Aidoku's yStart/yEnd nub offset (-0.15/0.15) is a fixed
				// constant sized for its own chapter-count axis (typically
				// single/low-double digits). This app's y-axis is words
				// read, often in the thousands, where a fixed 0.15 offset
				// would be visually imperceptible -- scaled proportionally
				// to maxY instead, to preserve the same "small visible nub
				// on a zero month" effect regardless of the word-count range.
				BarMark(
					x: .value("Month", month.rawValue),
					yStart: .value("Value", -0.15 * Double(maxY) / 10),
					yEnd: .value("Value", value == 0 ? 0.15 * Double(maxY) / 10 : Double(value)),
					width: 2
				)
				.foregroundStyle(.primary)
			}
		}
		.chartXScale(domain: 0.4...12.6)
		.chartYScale(domain: 0...maxY)
		.chartXAxis {
			// show first letter for each month
			AxisMarks(values: Array(1...12)) { value in
				let locale = Locale.current
				let isCJK = ["ja", "zh", "ko"].contains(locale.language.languageCode?.identifier ?? "")
				if
					let intValue = value.as(Int.self),
					let month = ReadingMonth(rawValue: intValue),
					!isCJK || (isCJK && intValue % 2 == 1) // skip every other in cjk (because labels are wider)
				{
					let value = data.value(for: month)
					AxisValueLabel(anchor: .top) {
						let xOffset: CGFloat = if #available(iOS 27.0, *) {
							-8
						} else {
							0
						}
						Text(month.axisLabel)
							.font(.caption2.weight(.semibold))
							.offset(x: xOffset, y: 2)
							.fixedSize()
					}
					.foregroundStyle(value == 0 ? .secondary : .primary)
				}
			}
		}
		.chartYAxis {
			// ideally show three marks: zero, mid, max
			AxisMarks(values: .automatic(desiredCount: 3)) { value in
				AxisGridLine()
				AxisValueLabel {
					if let intValue = value.as(Int.self) {
						Text(intValue, format: .number)
							.font(.system(size: 9, weight: .medium))
					}
				}
			}
		}
		.chartLegend(.hidden)
		.foregroundStyle(.primary) // by default it uses accent color
	}
}

#Preview {
	var data = ReadingMonthData()
	data.may = 8_000
	data.september = 9_500
	data.november = 12_000
	data.december = 1_200
	return ReadingYearlyMonthChartView(data: data)
		.frame(height: 104)
		.padding()
}
