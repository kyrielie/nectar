import Foundation
import SwiftUI
import Account
import Articles

struct ReadingStatsView: View {
	@State private var trackingEnabled = AppDefaults.shared.readingStatsTrackingEnabled
	@State private var month = false
	@AppStorage(AppDefaults.Key.highlightPalette) private var highlightPaletteRawValue = HighlightPalette.default.rawValue
	@Environment(\.colorScheme) private var colorScheme

	private var highlightPalette: HighlightPalette {
		HighlightPalette(rawValue: highlightPaletteRawValue) ?? .default
	}

	private var totals: ReadingStatsTotals {
		let end = Date()
		let start = Calendar.current.date(byAdding: .day, value: month ? -29 : -6, to: Calendar.current.startOfDay(for: end)) ?? end
		return ReadingStatsCalendar.totals(history: AppDefaults.shared.readingStatsDailyHistory, range: start...end, calendar: .current)
	}

	/// Always the trailing 7 days, independent of the week/month picker
	/// above -- a 30-bar chart doesn't read usefully at phone width, and
	/// the mockup this screen is built from only ever showed a 7-day
	/// view. The picker still scopes the metric cards and the fandom/tag
	/// breakdowns below; only this chart's window is fixed.
	private var dailyWordCounts: [(label: String, words: Int, isToday: Bool)] {
		let history = AppDefaults.shared.readingStatsDailyHistory
		let calendar = Calendar.current
		let keyFormatter = Self.dateKeyFormatter
		let today = calendar.startOfDay(for: Date())
		return (0..<7).reversed().compactMap { offset -> (String, Int, Bool)? in
			guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
			let key = keyFormatter.string(from: day)
			let words = history[key]?.wordsRead ?? 0
			return (Self.dayLetterFormatter.string(from: day), words, offset == 0)
		}
	}

	/// Top 4 fandoms by words this period, remainder folded into "Other" --
	/// mirrors the mockup's pie chart, and keeps the wedge count within
	/// Annotation.Color.allCases' 5 colors without a separate palette.
	private var fandomSlices: [(name: String, words: Int)] {
		let sorted = totals.byFandom.sorted { $0.value > $1.value }
		guard sorted.count > 4 else { return sorted.map { ($0.key, $0.value) } }
		let top = sorted.prefix(4).map { ($0.key, $0.value) }
		let other = sorted.dropFirst(4).reduce(0) { $0 + $1.value }
		return other > 0 ? top + [("Other", other)] : top
	}

	private var topTags: [(name: String, words: Int)] {
		Array(totals.byTag.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) })
	}

	var body: some View {
		List {
			Section {
				Toggle("Track reading activity", isOn: $trackingEnabled)
					.onChange(of: trackingEnabled) { _, value in AppDefaults.shared.readingStatsTrackingEnabled = value }
			} footer: {
				Text("When off, no new reading activity is recorded. Existing history is kept.")
			}

			Section {
				Picker("Period", selection: $month) {
					Text("This week").tag(false)
					Text("This month").tag(true)
				}
				.pickerStyle(.segmented)
				.labelsHidden()
			}
			.listRowSeparator(.hidden)

			Section("Summary") {
				metricsGrid
					.listRowInsets(EdgeInsets())
					.padding(.vertical, 8)
			}

			Section("Words per day") {
				dailyBarChart
					.listRowInsets(EdgeInsets())
					.padding(.vertical, 8)
			}

			if !fandomSlices.isEmpty {
				Section("By fandom") {
					fandomBreakdown
						.listRowInsets(EdgeInsets())
						.padding(.vertical, 8)
				}
			}

			if !topTags.isEmpty {
				Section("Top tags") {
					tagRankedBars
						.listRowInsets(EdgeInsets())
						.padding(.vertical, 8)
				}
			}

			// Only "total words read" is shown here -- that's the one
			// all-time counter that actually exists
			// (AppDefaults.readingStatsAllTimeWords, never pruned).
			// "Longest streak ever" and per-session stats (average/
			// longest session, most-read fandom all-time) aren't
			// tracked anywhere yet -- readingStatsDailyHistory only
			// keeps a rolling 35-day window, and there's no discrete
			// session log, just a daily secondsActive total. Showing
			// those here would mean fabricating numbers rather than
			// reading real data.
			Section("All time") {
				metricRow("Total words read", "\(AppDefaults.shared.readingStatsAllTimeWords)")
			}
		}
		.navigationTitle("Reading Stats")
		.navigationBarTitleDisplayMode(.inline)
	}

	private var metricsGrid: some View {
		LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
			metricCard("Words read", "\(totals.wordsRead)")
			metricCard("Words / hour", String(format: "%.0f", totals.wordsPerHour))
			metricCard("Works read", "\(totals.worksCompleted)")
			metricCard("Streak", "\(ReadingStatsCalendar.currentStreak(history: AppDefaults.shared.readingStatsDailyHistory, asOf: Date())) days")
		}
	}

	private func metricCard(_ label: String, _ value: String) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(label).font(.caption).foregroundStyle(.secondary)
			Text(value).font(.title3.weight(.semibold)).foregroundStyle(.primary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
	}

	private func metricRow(_ label: String, _ value: String) -> some View {
		HStack {
			Text(label)
			Spacer()
			Text(value).foregroundStyle(.secondary)
		}
	}

	private var dailyBarChart: some View {
		let counts = dailyWordCounts
		let maxWords = max(counts.map(\.words).max() ?? 0, 1)
		return VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .bottom, spacing: 6) {
				ForEach(Array(counts.enumerated()), id: \.offset) { _, day in
					RoundedRectangle(cornerRadius: 3, style: .continuous)
						.fill(day.isToday ? Color.accentColor : Color.accentColor.opacity(0.35))
						.frame(height: max(4, CGFloat(day.words) / CGFloat(maxWords) * 90))
						.frame(maxWidth: .infinity)
				}
			}
			.frame(height: 90, alignment: .bottom)
			HStack(spacing: 6) {
				ForEach(Array(counts.enumerated()), id: \.offset) { _, day in
					Text(day.label).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
				}
			}
		}
	}

	/// Filled pie wedges via a custom Shape rather than Swift Charts --
	/// this codebase has no existing `import Charts` anywhere and no
	/// checkable deployment target in this snapshot, so this avoids
	/// betting on an API that might not be available. Trim-on-a-stroked-
	/// Circle gives ring segments, not filled wedges, hence the Shape.
	private struct PieSlice: Shape {
		let startAngle: Angle
		let endAngle: Angle
		func path(in rect: CGRect) -> Path {
			var path = Path()
			let center = CGPoint(x: rect.midX, y: rect.midY)
			let radius = min(rect.width, rect.height) / 2
			path.move(to: center)
			path.addArc(center: center, radius: radius, startAngle: startAngle - .degrees(90), endAngle: endAngle - .degrees(90), clockwise: false)
			path.closeSubpath()
			return path
		}
	}

	/// One pre-computed pie wedge, with its angle span and color already
	/// resolved. Pulled out as its own type (rather than an inline tuple)
	/// so fandomBreakdown's body below is a single @ViewBuilder
	/// expression over already-typed data -- the previous inline
	/// let/var/map-into-tuple-array version in the same `some View`
	/// property forced the type checker to solve the tuple inference and
	/// the view hierarchy as one expression, which is what pushed
	/// fandomBreakdown over Xcode's per-expression type-check budget
	/// (717ms against the default 650ms limit). No behavior change --
	/// same wedges, same colors, same order.
	private struct FandomWedge: Identifiable {
		let id: Int
		let name: String
		let words: Int
		let color: Color
		let start: Angle
		let end: Angle
	}

	private func fandomWedges(for slices: [(name: String, words: Int)]) -> [FandomWedge] {
		let total = max(slices.reduce(0) { $0 + $1.words }, 1)
		var cumulative = 0.0
		return slices.enumerated().map { index, slice in
			let fraction = Double(slice.words) / Double(total)
			let start = Angle(degrees: cumulative * 360)
			cumulative += fraction
			let end = Angle(degrees: cumulative * 360)
			let color = Annotation.Color.allCases[index % Annotation.Color.allCases.count].swiftUIColor(palette: highlightPalette, isDark: colorScheme == .dark)
			return FandomWedge(id: index, name: slice.name, words: slice.words, color: color, start: start, end: end)
		}
	}

	private var fandomBreakdown: some View {
		let wedges = fandomWedges(for: fandomSlices)
		return HStack(spacing: 16) {
			fandomPieChart(wedges)
			fandomLegend(wedges)
		}
	}

	/// Split out of fandomBreakdown so each half is its own
	/// independently-type-checked @ViewBuilder expression -- even with
	/// FandomWedge's tuple-inference cost already removed (see that
	/// type's doc comment), the combined HStack/ZStack/VStack/ForEach/
	/// HStack tree in one property was still measured at 669ms against
	/// Xcode's 650ms per-expression budget. wedges is computed once in
	/// fandomBreakdown and passed down, rather than each half calling
	/// fandomWedges(for:) again, so splitting the view tree doesn't also
	/// double the per-render wedge computation. No behavior change.
	private func fandomPieChart(_ wedges: [FandomWedge]) -> some View {
		ZStack {
			ForEach(wedges) { wedge in
				PieSlice(startAngle: wedge.start, endAngle: wedge.end).fill(wedge.color)
			}
		}
		.frame(width: 110, height: 110)
	}

	private func fandomLegend(_ wedges: [FandomWedge]) -> some View {
		let total = max(wedges.reduce(0) { $0 + $1.words }, 1)
		return VStack(alignment: .leading, spacing: 8) {
			ForEach(wedges) { wedge in
				fandomLegendRow(wedge, total: total)
			}
		}
	}

	private func fandomLegendRow(_ wedge: FandomWedge, total: Int) -> some View {
		HStack(spacing: 8) {
			Circle().fill(wedge.color).frame(width: 10, height: 10)
			Text(wedge.name).font(.footnote).foregroundStyle(.primary).lineLimit(1)
			Spacer()
			Text("\(Int((Double(wedge.words) / Double(total) * 100).rounded()))%").font(.footnote).foregroundStyle(.secondary)
		}
	}

	/// Ranked bars rather than a second pie -- tags are long-tail (too many
	/// distinct values to pie-chart usefully), matching the split The
	/// StoryGraph's own stats page uses between its genre pie and its
	/// mood bar lists.
	private var tagRankedBars: some View {
		let tags = topTags
		let maxWords = max(tags.map(\.words).max() ?? 0, 1)
		return VStack(spacing: 8) {
			ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
				HStack(spacing: 8) {
					Text(tag.name).font(.footnote).foregroundStyle(.primary).lineLimit(1).frame(width: 110, alignment: .leading)
					GeometryReader { geo in
						RoundedRectangle(cornerRadius: 4, style: .continuous)
							.fill(Color.accentColor.opacity(0.7))
							.frame(width: geo.size.width * CGFloat(tag.words) / CGFloat(maxWords))
					}
					.frame(height: 8)
					Text("\(tag.words)").font(.caption2).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
				}
			}
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
