import SwiftUI
import Account

struct ScreenTimeSettingsView: View {
	@State private var enabled = AppDefaults.shared.screenTimeEnabled
	@State private var bedtimeEnabled = AppDefaults.shared.screenTimeBedtimeEnabled
	@State private var start = Self.minutesDate(AppDefaults.shared.screenTimeBedtimeStartMinutesFromMidnight)
	@State private var end = Self.minutesDate(AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight)
	@State private var limits = AppDefaults.shared.screenTimeDailyLimitMinutesByWeekday
	@State private var pendingConfirmation: PendingConfirmation?
	@State private var takeABreakMode = AppDefaults.shared.screenTimeTakeABreakMode
	@State private var breakReadingMinutes = AppDefaults.shared.screenTimeBreakReadingMinutes
	@State private var breakEnforcedMinutes = AppDefaults.shared.screenTimeBreakEnforcedMinutes
	// Sourced from ScreenTimeTracker.shared.activeReasons, kept in sync via
	// the same notifications the enforcement overlay reacts to, so the
	// banner below doesn't go stale while this screen is on screen.
	@State private var activeLockoutReasons: Set<ScreenTimeTracker.Reason> = ScreenTimeTracker.shared.activeReasons
	// 0 = the current Sunday-start calendar week; increasing goes further
	// into the past. See weeklySummarySection/weekStart below.
	@State private var weeksBack = 0

	private let weekdays = Calendar.current.weekdaySymbols

	private struct PendingConfirmation: Identifiable {
		enum Kind { case screenTimeEnable, bedtimeSpan }
		let id = UUID()
		let kind: Kind
		let message: String
		let revert: () -> Void
	}

	var body: some View {
		Form {
			weeklySummarySection

			if let status = ScreenTimeTracker.lockoutStatus(for: activeLockoutReasons, bedtimeEndMinutesFromMidnight: AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight) {
				Section {
					Label(status.message, systemImage: status.systemImageName)
						.foregroundStyle(.secondary)
				}
			}

			Section {
				Toggle("Enable Screen Time", isOn: $enabled)
					.onChange(of: enabled) { _, value in
						AppDefaults.shared.screenTimeEnabled = value
						if value {
							pendingConfirmation = PendingConfirmation(
								kind: .screenTimeEnable,
								message: "Reading will be blocked immediately once today's limit or bedtime window is reached.",
								revert: {
									enabled = false
									AppDefaults.shared.screenTimeEnabled = false
								}
							)
						}
					}
			} footer: { Text("When enabled, reading is blocked immediately after the daily limit or bedtime window begins.") }

			Section("Daily limits") {
				ForEach(1...7, id: \.self) { weekday in
					NavigationLink {
						DailyLimitDetailView(
							weekdayName: weekdays[weekday - 1],
							minutes: Binding(
								get: { limits[weekday, default: 120] },
								set: { newValue in
									limits[weekday] = newValue
									AppDefaults.shared.setScreenTimeDailyLimitMinutes(newValue, for: weekday)
								}
							)
						)
					} label: {
						HStack {
							Text(weekdays[weekday - 1])
							Spacer()
							Text(durationString(limits[weekday, default: 120])).foregroundStyle(.secondary)
						}
					}
				}
			}

			Section("Bedtime") {
				Toggle("Enable bedtime", isOn: $bedtimeEnabled)
					.onChange(of: bedtimeEnabled) { _, value in AppDefaults.shared.screenTimeBedtimeEnabled = value }
				DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
					.onChange(of: start) { _, value in updateBedtimeStart(value) }
				DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
					.onChange(of: end) { _, value in updateBedtimeEnd(value) }
			}

			takeABreakSection
		}
		.navigationTitle("Screen Time")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear { activeLockoutReasons = ScreenTimeTracker.shared.activeReasons }
		.onReceive(NotificationCenter.default.publisher(for: .screenTimeLimitReached)) { _ in
			activeLockoutReasons = ScreenTimeTracker.shared.activeReasons
		}
		.onReceive(NotificationCenter.default.publisher(for: .screenTimeEnforcementDidClear)) { _ in
			activeLockoutReasons = []
		}
		.alert(item: $pendingConfirmation) { confirmation in
			Alert(
				title: Text("Confirm Screen Time setting"),
				message: Text(confirmation.message),
				primaryButton: .default(Text("Keep")),
				secondaryButton: .cancel(Text("Undo"), action: confirmation.revert)
			)
		}
	}

	/// Pulled out of `body` as its own property -- like `fandomBreakdown`/
	/// `fandomPieChart` in ReadingStatsView, a Section this size (picker +
	/// two conditional NavigationLinks + a switch in the footer) inline in
	/// `body` alongside the other five sections pushed the whole `body`
	/// getter over Xcode's per-expression type-check budget. No behavior
	/// change from having this be a separate property.
	private var takeABreakSection: some View {
		Section {
			Picker("Mode", selection: $takeABreakMode) {
				Text("Off").tag(TakeABreakMode.off)
				Text("Reminder").tag(TakeABreakMode.reminder)
				Text("Enforced").tag(TakeABreakMode.enforced)
			}
			.onChange(of: takeABreakMode) { _, value in AppDefaults.shared.screenTimeTakeABreakMode = value }

			if takeABreakMode != .off {
				takeABreakTimerRow(
					title: "Reading Time",
					footer: "How long to read before a break is triggered.",
					minutes: $breakReadingMinutes,
					store: { AppDefaults.shared.screenTimeBreakReadingMinutes = $0 }
				)
			}

			if takeABreakMode == .enforced {
				takeABreakTimerRow(
					title: "Break Time",
					footer: "How long reading is blocked for once a break is triggered.",
					minutes: $breakEnforcedMinutes,
					store: { AppDefaults.shared.screenTimeBreakEnforcedMinutes = $0 }
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
		switch takeABreakMode {
		case .off:
			Text("No break reminders while reading.")
		case .reminder:
			Text("Shows a dismissible reminder every \(durationString(breakReadingMinutes)) of continuous reading.")
		case .enforced:
			Text("Blocks reading for \(durationString(breakEnforcedMinutes)) every \(durationString(breakReadingMinutes)) of continuous reading.")
		}
	}

	/// Shared row for both Take a Break timer settings -- same
	/// NavigationLink-to-CountDownTimerSettingView shape, differing only
	/// in title/footer copy and which AppDefaults property they write to.
	private func takeABreakTimerRow(title: String, footer: String, minutes: Binding<Int>, store: @escaping (Int) -> Void) -> some View {
		NavigationLink {
			CountDownTimerSettingView(
				title: title,
				footer: footer,
				minutes: Binding(
					get: { minutes.wrappedValue },
					set: { newValue in
						minutes.wrappedValue = newValue
						store(newValue)
					}
				)
			)
		} label: {
			HStack {
				Text(title)
				Spacer()
				Text(durationString(minutes.wrappedValue)).foregroundStyle(.secondary)
			}
		}
	}

	private func updateBedtimeStart(_ value: Date) {
		let newStart = minutes(value)
		let oldStart = minutes(start)
		let span = ScreenTimeCalendar.bedtimeWindowSpanMinutes(startMinutes: newStart, endMinutes: minutes(end))
		AppDefaults.shared.screenTimeBedtimeStartMinutesFromMidnight = newStart
		if span > ScreenTimeCalendar.maxBedtimeWindowSpanMinutes {
			// AppDefaults' setter already clamped `end`; re-read the stored value.
			let clampedEnd = AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight
			end = Self.minutesDate(clampedEnd)
			pendingConfirmation = PendingConfirmation(
				kind: .bedtimeSpan,
				message: "Bedtime can't be longer than 12 hours, so the end time was moved to \(Self.timeString(end)). Reading will be blocked for the full 12 hours.",
				revert: {
					start = Self.minutesDate(oldStart)
					AppDefaults.shared.screenTimeBedtimeStartMinutesFromMidnight = oldStart
				}
			)
		}
	}

	private func updateBedtimeEnd(_ value: Date) {
		let newEnd = minutes(value)
		let oldEnd = minutes(end)
		let span = ScreenTimeCalendar.bedtimeWindowSpanMinutes(startMinutes: minutes(start), endMinutes: newEnd)
		AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight = newEnd
		if span > ScreenTimeCalendar.maxBedtimeWindowSpanMinutes {
			let clampedStart = AppDefaults.shared.screenTimeBedtimeStartMinutesFromMidnight
			start = Self.minutesDate(clampedStart)
			pendingConfirmation = PendingConfirmation(
				kind: .bedtimeSpan,
				message: "Bedtime can't be longer than 12 hours, so the start time was moved to \(Self.timeString(start)). Reading will be blocked for the full 12 hours.",
				revert: {
					end = Self.minutesDate(oldEnd)
					AppDefaults.shared.screenTimeBedtimeEndMinutesFromMidnight = oldEnd
				}
			)
		}
	}

	private func minutes(_ date: Date) -> Int { let c = Calendar.current.dateComponents([.hour, .minute], from: date); return (c.hour ?? 0) * 60 + (c.minute ?? 0) }
	private static func minutesDate(_ value: Int) -> Date { Calendar.current.date(from: DateComponents(hour: value / 60, minute: value % 60)) ?? Date() }
	private static func timeString(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.timeStyle = .short
		return formatter.string(from: date)
	}

	// MARK: Weekly summary

	private struct DailyUsage: Identifiable {
		let id: String
		let label: String
		let minutesUsed: Int
		let limitMinutes: Int
		let isToday: Bool
	}

	/// Sunday-start regardless of device locale, per explicit request --
	/// not Calendar.current, whose firstWeekday follows the user's locale.
	private static var sundayCalendar: Calendar = {
		var calendar = Calendar(identifier: .gregorian)
		calendar.firstWeekday = 1
		return calendar
	}()

	/// How many weeks back "Previous" will go. Bounded by how far back
	/// screenTimeDailyUsageHistory actually retains data (35 days / 5
	/// weeks including the current one -- see AppDefaults'
	/// screenTimeDailyUsageHistory), so the navigator never lands on a
	/// week that's guaranteed to show as empty.
	private static let maxWeeksBack = 4

	private var weekStart: Date {
		let calendar = Self.sundayCalendar
		let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
		return calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: currentWeekStart) ?? currentWeekStart
	}

	private var weeklyUsage: [DailyUsage] {
		let calendar = Self.sundayCalendar
		let history = AppDefaults.shared.screenTimeDailyUsageHistory
		let today = calendar.startOfDay(for: Date())
		let start = weekStart
		return (0..<7).compactMap { offset -> DailyUsage? in
			guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
			let key = Self.dateKeyFormatter.string(from: day)
			let weekday = calendar.component(.weekday, from: day)
			return DailyUsage(id: key, label: Self.dayLetterFormatter.string(from: day), minutesUsed: history[key] ?? 0, limitMinutes: AppDefaults.shared.screenTimeDailyLimitMinutes(for: weekday), isToday: calendar.isDate(day, inSameDayAs: today))
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

	private var weeklySummarySection: some View {
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

			if AppDefaults.shared.screenTimeDailyUsageHistory.isEmpty {
				Text("No Screen Time history yet.").foregroundStyle(.secondary)
			} else {
				weeklyUsageBarChart
					.listRowInsets(EdgeInsets())
					.padding(.vertical, 8)
			}
		}
	}

	/// Bar height is minutes used; the thin line across each bar marks
	/// that day's configured limit, so going over reads immediately as
	/// "bar taller than its own line" rather than requiring a lookup
	/// against a list below. Both bar height and line position share one
	/// scale (maxValue below) so the line's vertical position is
	/// comparable across days even as each day's own limit changes.
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
/// in ScreenTimeSettingsView and DailyLimitDetailView's footer, so the
/// two can't drift out of sync with each other's wording -- the same
/// reasoning that motivated ScreenTimeTracker.lockoutStatus(for:
/// bedtimeEndMinutesFromMidnight:), though that one is currently only
/// consumed here, not by ScreenTimeEnforcementOverlay -- see
/// lockoutStatus's own doc comment.
private func durationString(_ minutes: Int) -> String {
	let hours = minutes / 60
	let mins = minutes % 60
	if hours == 0 { return "\(mins)m" }
	if mins == 0 { return "\(hours)h" }
	return "\(hours)h \(mins)m"
}

/// Pushed from ScreenTimeSettingsView's "Take a Break" section for either
/// of its two timer settings (reading time, enforced break time). Same
/// countDownTimer-wheel-on-its-own-screen shape as DailyLimitDetailView
/// below, minus that view's daily-limit-specific "strict limit" confirm
/// dialog -- neither break timer has an equivalent "going under 2 hours
/// blocks reading" threshold to warn about.
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

/// Pushed per weekday from ScreenTimeSettingsView's "Daily limits"
/// section -- the countDownTimer wheel (see CountDownTimerPicker) is too
/// tall to sit inline in a Form row alongside six other weekdays, so each
/// weekday gets its own screen, matching how Settings → Screen Time →
/// App Limits → Add Limit is its own pushed screen in iOS Screen Time.
private struct DailyLimitDetailView: View {
	let weekdayName: String
	@Binding var minutes: Int
	@State private var pendingConfirmation: PendingConfirmation?

	private struct PendingConfirmation: Identifiable {
		let id = UUID()
		let message: String
		let revert: () -> Void
	}

	var body: some View {
		Form {
			Section {
				CountDownTimerPicker(minutes: $minutes)
					.onChange(of: minutes) { oldValue, newValue in
						if newValue < 120, oldValue >= 120 {
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
