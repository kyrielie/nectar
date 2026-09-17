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
			.disabled(!enabled)
			.opacity(enabled ? 1 : 0.4)

			Section("Bedtime") {
				Toggle("Enable bedtime", isOn: $bedtimeEnabled)
					.onChange(of: bedtimeEnabled) { _, value in AppDefaults.shared.screenTimeBedtimeEnabled = value }
				DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
					.onChange(of: start) { _, value in AppDefaults.shared.screenTimeBedtimeStartMinutesFromMidnight = minutes(value) }
				DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
					.onChange(of: end) { _, value in AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight = minutes(value) }
			}
			.disabled(!enabled)
			.opacity(enabled ? 1 : 0.4)

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

	private struct DailyUsage: Identifiable {
		let id: String
		let label: String
		let minutesUsed: Int
		let limitMinutes: Int
		let isToday: Bool
	}

	private var dailyUsage: [DailyUsage] {
		let history = AppDefaults.shared.screenTimeDailyUsageHistory
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: Date())
		return (0..<7).reversed().compactMap { offset -> DailyUsage? in
			guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
			let key = Self.dateKeyFormatter.string(from: day)
			let weekday = calendar.component(.weekday, from: day)
			return DailyUsage(id: key, label: Self.dayLetterFormatter.string(from: day), minutesUsed: history[key] ?? 0, limitMinutes: AppDefaults.shared.screenTimeDailyLimitMinutes(for: weekday), isToday: offset == 0)
		}
	}

	var body: some View {
		List {
			if AppDefaults.shared.screenTimeDailyUsageHistory.isEmpty {
				Section {
					Text("No Screen Time history yet.").foregroundStyle(.secondary)
				}
			} else {
				Section("Minutes used, last 7 days") {
					usageBarChart
						.listRowInsets(EdgeInsets())
						.padding(.vertical, 8)
				}
				Section {
					ForEach(dailyUsage) { day in
						HStack {
							Text(day.id)
							Spacer()
							Text("\(day.minutesUsed) / \(day.limitMinutes) min")
								.foregroundStyle(day.minutesUsed > day.limitMinutes ? .red : .secondary)
						}
					}
				}
			}
		}
		.navigationTitle("Weekly summary")
		.navigationBarTitleDisplayMode(.inline)
	}

	/// Bar height is minutes used; the thin line across each bar marks
	/// that day's configured limit, so going over reads immediately as
	/// "bar taller than its own line" rather than requiring a lookup
	/// against the list below. Both bar height and line position share
	/// one scale (maxValue below) so the line's vertical position is
	/// comparable across days even as each day's own limit changes.
	private var usageBarChart: some View {
		let days = dailyUsage
		let maxValue = max(days.map { max($0.minutesUsed, $0.limitMinutes) }.max() ?? 1, 1)
		let chartHeight: CGFloat = 100
		return VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .bottom, spacing: 6) {
				ForEach(days) { day in
					ZStack(alignment: .bottom) {
						RoundedRectangle(cornerRadius: 3, style: .continuous)
							.fill(day.minutesUsed > day.limitMinutes ? Color.red.opacity(0.8) : (day.isToday ? Color.accentColor : Color.accentColor.opacity(0.35)))
							.frame(height: max(4, CGFloat(day.minutesUsed) / CGFloat(maxValue) * chartHeight))
						Rectangle()
							.fill(Color.secondary)
							.frame(height: 1.5)
							.offset(y: -CGFloat(day.limitMinutes) / CGFloat(maxValue) * chartHeight)
					}
					.frame(maxWidth: .infinity)
				}
			}
			.frame(height: chartHeight, alignment: .bottom)
			HStack(spacing: 6) {
				ForEach(days) { day in
					Text(day.label).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
				}
			}
			Text("Line marks that day's limit").font(.caption2).foregroundStyle(.secondary)
		}
	}

	private static let dateKeyFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()

	private static let dayLetterFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "EEEEE"
		return formatter
	}()
}
