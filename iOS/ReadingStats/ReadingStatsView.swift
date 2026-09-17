import Foundation
import SwiftUI
import Account

struct ReadingStatsView: View {
	@State private var trackingEnabled = AppDefaults.shared.readingStatsTrackingEnabled
	@State private var month = false

	private var totals: ReadingStatsTotals {
		let end = Date()
		let start = Calendar.current.date(byAdding: .day, value: month ? -29 : -6, to: Calendar.current.startOfDay(for: end)) ?? end
		return ReadingStatsCalendar.totals(history: AppDefaults.shared.readingStatsDailyHistory, range: start...end, calendar: .current)
	}

	var body: some View {
		List {
			Section { Toggle("Track reading activity", isOn: $trackingEnabled).onChange(of: trackingEnabled) { _, value in AppDefaults.shared.readingStatsTrackingEnabled = value } }
			Picker("Period", selection: $month) { Text("This week").tag(false); Text("This month").tag(true) }.pickerStyle(.segmented)
			Section("Summary") {
				metric("Words read", "\(totals.wordsRead)")
				metric("Words per hour", String(format: "%.0f", totals.wordsPerHour))
				metric("Works completed", "\(totals.worksCompleted)")
				metric("Current streak", "\(ReadingStatsCalendar.currentStreak(history: AppDefaults.shared.readingStatsDailyHistory, asOf: Date())) days")
			}
			Section("Top tags") {
				ForEach(totals.byTag.sorted { $0.value > $1.value }.prefix(5), id: \.key) { Text("\($0.key) — \($0.value)") }
			}
		}
		.navigationTitle("Reading Stats")
		.navigationBarTitleDisplayMode(.inline)
	}

	private func metric(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) } }
}
