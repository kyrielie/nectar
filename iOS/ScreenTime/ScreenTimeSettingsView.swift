import SwiftUI
import Account

struct ScreenTimeSettingsView: View {
	@State private var enabled = AppDefaults.shared.screenTimeEnabled
	@State private var bedtimeEnabled = AppDefaults.shared.screenTimeBedtimeEnabled
	@State private var start = Self.minutesDate(AppDefaults.shared.screenTimeBedtimeStartMinutesFromMidnight)
	@State private var end = Self.minutesDate(AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight)
	@State private var limits = AppDefaults.shared.screenTimeDailyLimitMinutesByWeekday

	private let weekdays = Calendar.current.weekdaySymbols

	var body: some View {
		Form {
			Section {
				Toggle("Enable Screen Time", isOn: $enabled)
					.onChange(of: enabled) { _, value in AppDefaults.shared.screenTimeEnabled = value }
			} footer: { Text("When enabled, reading is blocked immediately after the daily limit or bedtime window begins.") }
			Section("Daily limits") {
				ForEach(1...7, id: \.self) { weekday in
					Stepper("\(weekdays[weekday - 1]): \(limits[weekday, default: 120]) minutes", value: Binding(get: { limits[weekday, default: 120] }, set: { limits[weekday] = $0; AppDefaults.shared.setScreenTimeDailyLimitMinutes($0, for: weekday) }), in: 1...1440, step: 15)
				}
			}
			Section("Bedtime") {
				Toggle("Enable bedtime", isOn: $bedtimeEnabled)
					.onChange(of: bedtimeEnabled) { _, value in AppDefaults.shared.screenTimeBedtimeEnabled = value }
				DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
					.onChange(of: start) { _, value in AppDefaults.shared.screenTimeBedtimeStartMinutesFromMidnight = minutes(value) }
				DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
					.onChange(of: end) { _, value in AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight = minutes(value) }
			}
			Section {
				NavigationLink("Weekly summary") { ScreenTimeSummaryView() }
			}
		}
		.navigationTitle("Screen Time")
		.navigationBarTitleDisplayMode(.inline)
	}

	private func minutes(_ date: Date) -> Int { let c = Calendar.current.dateComponents([.hour, .minute], from: date); return (c.hour ?? 0) * 60 + (c.minute ?? 0) }
	private static func minutesDate(_ value: Int) -> Date { Calendar.current.date(from: DateComponents(hour: value / 60, minute: value % 60)) ?? Date() }
}

struct ScreenTimeSummaryView: View {
	var body: some View {
		List {
			ForEach(Array(AppDefaults.shared.screenTimeDailyUsageHistory.keys.sorted().suffix(7)), id: \.self) { key in
				HStack { Text(key); Spacer(); Text("\(AppDefaults.shared.screenTimeDailyUsageHistory[key, default: 0]) min") }
			}
			if AppDefaults.shared.screenTimeDailyUsageHistory.isEmpty { Text("No Screen Time history yet.").foregroundStyle(.secondary) }
		}
		.navigationTitle("Weekly summary")
	}
}
