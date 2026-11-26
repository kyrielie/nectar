import SwiftUI
import ReadingTime
import Account

struct ReadingTimeSettingsView: View {
	@StateObject private var model = ReadingTimeSettingsModel()
	@State private var weeksBack = 0

	var body: some View {
		Form {
			ReadingTimeWeeklySummarySection(weeksBack: $weeksBack)

			if let status = ReadingTimeTracker.lockoutStatus(for: model.activeLockoutReasons, bedtimeEndMinutesFromMidnight: AppDefaults.shared.readingTimeBedtimeEndMinutesFromMidnight) {
				Section {
					Label(status.message, systemImage: status.systemImageName)
						.foregroundStyle(.secondary)
				}
			}

			Section {
				Toggle("Enable Reading Time", isOn: $model.enabled)
			} footer: {
				Text("When enabled, reading is blocked immediately once today's limit or bedtime window is reached. Configure your limits, bedtime, and break reminders below.")
			}

			ReadingTimeDailyLimitsSection(model: model)
				.disabled(!model.enabled)
				.opacity(model.enabled ? 1 : 0.4)

			ReadingTimeBedtimeSection(model: model)
				.disabled(!model.enabled)
				.opacity(model.enabled ? 1 : 0.4)

			ReadingTimeTakeABreakSection(model: model)
				.disabled(!model.enabled)
				.opacity(model.enabled ? 1 : 0.4)

			Section {
				Toggle("Show indicator while reading", isOn: $model.indicatorEnabled)
			} footer: {
				Text("Shows a small pie indicator of today's remaining reading time in fullscreen reading, independent of the Page Counter setting.")
			}
		}
		.navigationTitle("Reading Time")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear { model.refreshLockoutReasons() }
		.alert(item: $model.pendingConfirmation) { confirmation in
			Alert(
				title: Text("Confirm Reading Time setting"),
				message: Text(confirmation.message),
				primaryButton: .default(Text("Keep")),
				secondaryButton: .cancel(Text("Undo"), action: confirmation.revert)
			)
		}
	}
}

private struct ReadingTimeDailyLimitsSection: View {
	@ObservedObject var model: ReadingTimeSettingsModel
	private let weekdays = Calendar.current.weekdaySymbols

	var body: some View {
		Section("Daily Limits") {
			Toggle("Enable Daily Limit", isOn: $model.dailyLimitEnabled)
			ForEach(1...7, id: \.self) { weekday in
				NavigationLink {
					DailyLimitDetailView(
						weekdayName: weekdays[weekday - 1],
						minutes: Binding(
							get: { model.limits[weekday, default: 120] },
							set: { model.setDailyLimitMinutes($0, for: weekday) }
						)
					)
				} label: {
					LabeledContent(weekdays[weekday - 1], value: durationString(model.limits[weekday, default: 120]))
				}
			}
		}
	}
}

private struct ReadingTimeBedtimeSection: View {
	@ObservedObject var model: ReadingTimeSettingsModel

	var body: some View {
		Section("Bedtime") {
			Toggle("Enable Bedtime", isOn: $model.bedtimeEnabled)
			DatePicker(
				"Starts",
				selection: Binding(
					get: { model.start },
					set: { newValue in
						model.start = newValue
						model.updateBedtimeStart(newValue)
					}
				),
				displayedComponents: .hourAndMinute
			)
			DatePicker(
				"Ends",
				selection: Binding(
					get: { model.end },
					set: { newValue in
						model.end = newValue
						model.updateBedtimeEnd(newValue)
					}
				),
				displayedComponents: .hourAndMinute
			)
		}
	}
}

private struct ReadingTimeTakeABreakSection: View {
	@ObservedObject var model: ReadingTimeSettingsModel

	var body: some View {
		Section {
			Picker("Mode", selection: $model.takeABreakMode) {
				Text("Off").tag(TakeABreakMode.off)
				Text("Reminder").tag(TakeABreakMode.reminder)
				Text("Enforced").tag(TakeABreakMode.enforced)
			}

			if model.takeABreakMode != .off {
				takeABreakTimerRow(
					title: "Reading Time",
					footer: "How long to read before a break is triggered.",
					minutes: $model.breakReadingMinutes
				)
			}

			if model.takeABreakMode == .enforced {
				takeABreakTimerRow(
					title: "Break Time",
					footer: "How long reading is blocked for once a break is triggered.",
					minutes: $model.breakEnforcedMinutes
				)
			}
		} header: {
			Text("Take a Break")
		} footer: {
			takeABreakFooterText
		}
	}

	@ViewBuilder
	private var takeABreakFooterText: some View {
		switch model.takeABreakMode {
		case .off:
			Text("No break reminders while reading.")
		case .reminder:
			Text("Shows a dismissible reminder every \(durationString(model.breakReadingMinutes)) of continuous reading.")
		case .enforced:
			Text("Blocks reading for \(durationString(model.breakEnforcedMinutes)) every \(durationString(model.breakReadingMinutes)) of continuous reading.")
		}
	}

	private func takeABreakTimerRow(title: String, footer: String, minutes: Binding<Int>) -> some View {
		NavigationLink {
			CountDownTimerSettingView(title: title, footer: footer, minutes: minutes)
		} label: {
			LabeledContent(title, value: durationString(minutes.wrappedValue))
		}
	}
}

private struct ReadingTimeWeeklySummarySection: View {
	@Binding var weeksBack: Int

	private struct DailyUsage: Identifiable {
		let id: String
		let label: String
		let minutesUsed: Int
		let limitMinutes: Int
		let isToday: Bool
	}

	private static var sundayCalendar: Calendar = {
		var calendar = Calendar(identifier: .gregorian)
		calendar.firstWeekday = 1
		return calendar
	}()

	private static let maxWeeksBack = 4

	private var weekStart: Date {
		let calendar = Self.sundayCalendar
		let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
		return calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: currentWeekStart) ?? currentWeekStart
	}

	private var weeklyUsage: [DailyUsage] {
		let calendar = Self.sundayCalendar
		let history = AppDefaults.shared.readingTimeDailyUsageHistory
		let today = calendar.startOfDay(for: Date())
		let start = weekStart
		return (0..<7).compactMap { offset -> DailyUsage? in
			guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
			let key = Self.dateKeyFormatter.string(from: day)
			let weekday = calendar.component(.weekday, from: day)
			return DailyUsage(
				id: key,
				label: Self.dayLetterFormatter.string(from: day),
				minutesUsed: history[key] ?? 0,
				limitMinutes: AppDefaults.shared.readingTimeDailyLimitMinutes(for: weekday),
				isToday: calendar.isDate(day, inSameDayAs: today)
			)
		}
	}

	private var weekRangeLabel: String {
		let calendar = Self.sundayCalendar
		let start = weekStart
		let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
		let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
		let startString = Self.monthDayFormatter.string(from: start)
		let endString = sameMonth ? Self.dayOnlyFormatter.string(from: end) : Self.monthDayFormatter.string(from: end)
		return "Week of \(startString)–\(endString)"
	}

	var body: some View {
		Section {
			HStack {
				Button {
					weeksBack += 1
				} label: {
					Image(systemName: "chevron.left")
				}
				.disabled(weeksBack >= Self.maxWeeksBack)

				Spacer()
				Text(weekRangeLabel).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
				Spacer()

				Button {
					weeksBack -= 1
				} label: {
					Image(systemName: "chevron.right")
				}
				.disabled(weeksBack <= 0)
			}
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)

			if AppDefaults.shared.readingTimeDailyUsageHistory.isEmpty {
				Text("No Reading Time history yet.").foregroundStyle(.secondary)
			} else {
				weeklyUsageBarChart
					.listRowInsets(EdgeInsets())
					.padding(.vertical, 8)
					.padding(.horizontal, 16)
			}
		}
	}

	private var weeklyUsageBarChart: some View {
		let days = weeklyUsage
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

	private static let monthDayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "MMM d"
		return formatter
	}()

	private static let dayOnlyFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "d"
		return formatter
	}()
}

/// "Xh Ym" duration formatting shared between the daily-limits row labels
/// in ReadingTimeSettingsView and DailyLimitDetailView's footer.
private func durationString(_ minutes: Int) -> String {
	let hours = minutes / 60
	let mins = minutes % 60
	if hours == 0 { return "\(mins)m" }
	if mins == 0 { return "\(hours)h" }
	return "\(hours)h \(mins)m"
}

private struct CountDownTimerSettingView: View {
	let title: String
	let footer: String
	@Binding var minutes: Int

	var body: some View {
		Form {
			Section {
				CountDownTimerPicker(minutes: $minutes)
					.frame(maxWidth: .infinity)
					.listRowInsets(EdgeInsets())
			} footer: {
				Text(footer)
			}
		}
		.navigationTitle(title)
		.navigationBarTitleDisplayMode(.inline)
	}
}

/// Decides when lowering a daily limit needs the "this is a strict limit"
/// confirmation. Pure so it can be tested without a view.
enum StrictLimitConfirmation {
	/// Limits below this many minutes are "strict" and ask for confirmation.
	static let thresholdMinutes = 120

	/// True when a change crosses from at-or-above the threshold to below it.
	static func needsConfirmation(from oldMinutes: Int, to newMinutes: Int) -> Bool {
		newMinutes < thresholdMinutes && oldMinutes >= thresholdMinutes
	}
}

private struct DailyLimitDetailView: View {
	let weekdayName: String
	@Binding var minutes: Int
	@State private var pendingConfirmation: PendingConfirmation?
	@State private var previousMinutes: Int?

	private struct PendingConfirmation: Identifiable {
		let id = UUID()
		let message: String
		let revert: () -> Void
	}

	var body: some View {
		Form {
			Section {
				CountDownTimerPicker(minutes: $minutes)
					.onAppear { previousMinutes = minutes }
					.onChange(of: minutes) { newValue in
						let oldValue = previousMinutes ?? newValue
						previousMinutes = newValue
						if StrictLimitConfirmation.needsConfirmation(from: oldValue, to: newValue) {
							pendingConfirmation = PendingConfirmation(
								message: "\(weekdayName) is set to \(durationString(newValue)). This is a strict limit — reading will be blocked once it's reached.",
								revert: { minutes = oldValue }
							)
						}
					}
					.frame(maxWidth: .infinity)
					.listRowInsets(EdgeInsets())
			} footer: {
				Text("Reading is blocked for the rest of \(weekdayName) once this limit is reached.")
			}
		}
		.navigationTitle(weekdayName)
		.navigationBarTitleDisplayMode(.inline)
		.alert(item: $pendingConfirmation) { confirmation in
			Alert(
				title: Text("Confirm daily limit"),
				message: Text(confirmation.message),
				primaryButton: .default(Text("Keep")),
				secondaryButton: .cancel(Text("Undo"), action: confirmation.revert)
			)
		}
	}
}
