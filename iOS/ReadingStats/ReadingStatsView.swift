import Foundation
import ReadingStats
import AppChrome
import SwiftUI
import Account
import Articles

enum StatsMetric { case words, works }

struct ReadingStatsView: View {
	@StateObject private var model = ReadingStatsModel()
	@State private var showingDeleteConfirmation = false
	@AppStorage(AppDefaults.Key.highlightPalette) private var highlightPaletteRawValue = HighlightPalette.default.rawValue
	@Environment(\.colorScheme) private var colorScheme

	private var highlightPalette: HighlightPalette {
		HighlightPalette(rawValue: highlightPaletteRawValue) ?? .default
	}

	var body: some View {
		List {
			Section {
				Toggle("Track reading activity", isOn: $model.trackingEnabled)
			} footer: {
				Text("When off, no new reading activity is recorded. Existing history is kept.")
			}

			Section {
				Picker("Period", selection: $model.isMonthlyPeriod) {
					Text("Last 7 days").tag(false)
					Text("Last 30 days").tag(true)
				}
				.pickerStyle(.segmented)
				.labelsHidden()
			}
			.listRowSeparator(.hidden)

			Section {
				Picker("Metric", selection: $model.statsMetric) {
					Text("Words").tag(StatsMetric.words)
					Text("Works").tag(StatsMetric.works)
				}
				.pickerStyle(.segmented)
				.labelsHidden()
			} footer: {
				Text("Controls both the fandom breakdown and top tags below.")
			}
			.listRowSeparator(.hidden)

			Section("Summary") {
				ReadingStatsSummaryGrid(totals: model.totals, currentStreak: model.streaks.current)
					.listRowInsets(EdgeInsets())
					.padding(.vertical, 8)
			}

			if !model.fandomSlices.isEmpty {
				Section {
					ReadingStatsFandomBreakdownView(
						slices: model.fandomSlices,
						highlightPalette: highlightPalette,
						isDark: colorScheme == .dark
					)
					.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
				} header: {
					Text("By fandom")
				} footer: {
					Text(model.statsMetric == .words
						? "A work's full word count counts toward every fandom it carries, so this can add up to more than total words read."
						: "A completed work counts toward every fandom it carries.")
				}
			}

			if !model.topTags.isEmpty {
				Section {
					ReadingStatsTagBarsView(tags: model.topTags, statsMetric: model.statsMetric)
						.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
				} header: {
					Text("Top tags")
				} footer: {
					Text(model.statsMetric == .words
						? "A work's full word count counts toward every tag it carries, so this can add up to more than total words read."
						: "A completed work counts toward every tag it carries.")
				}
			}

			Section {
				let lengths = model.streaks
				ReadingStreaksView(
					currentStreak: lengths.current,
					longestStreak: lengths.longest,
					heatmapData: ReadingStatsCalendar.heatmapData(dailyWords: model.dailyWords)
				)
				.listRowBackground(Color.clear)
				.listRowSeparator(.hidden)
				.listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
			} header: {
				Text("Streaks")
			} footer: {
				Text("A day counts toward a streak once any words are credited that day. Darker squares mean more words read.")
			}

			if !model.yearlyMonthData.isEmpty {
				Section("Monthly") {
					ReadingMonthlyChartCard(chartData: model.yearlyMonthData)
						.listRowBackground(Color.clear)
						.listRowSeparator(.hidden)
						.listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
				}
			}

			Section("All time") {
				LabeledContent("Total words read", value: "\(model.allTimeWords)")
			}

			Section {
				Button("Delete Reading Stats", role: .destructive) {
					showingDeleteConfirmation = true
				}
			} footer: {
				Text("Permanently deletes all recorded reading history, per-work progress, and the all-time word count. This can't be undone.")
			}
		}
		.navigationTitle("Reading Stats")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear { model.reload() }
		.confirmationDialog(
			"Delete all reading stats?",
			isPresented: $showingDeleteConfirmation,
			titleVisibility: .visible
		) {
			Button("Delete Reading Stats", role: .destructive) {
				model.resetReadingStats()
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("This permanently deletes all recorded reading history, per-work progress, and the all-time word count. This can't be undone.")
		}
	}
}

private struct ReadingStatsSummaryGrid: View {
	let totals: ReadingStatsTotals
	let currentStreak: Int

	var body: some View {
		LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
			metricCard("Words read", "\(totals.wordsRead)")
			metricCard("Words / hour", String(format: "%.0f", totals.wordsPerHour))
			metricCard("Works read", "\(totals.worksCompleted)")
			metricCard("Streak", "\(currentStreak > 1 ? currentStreak : 0) days")
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
}

private struct ReadingStatsFandomBreakdownView: View {
	let slices: [(name: String, value: Int)]
	let highlightPalette: HighlightPalette
	let isDark: Bool

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

	private struct FandomWedge: Identifiable {
		let id: Int
		let name: String
		let value: Int
		let color: Color
		let start: Angle
		let end: Angle
	}

	private var wedges: [FandomWedge] {
		let total = max(slices.reduce(0) { $0 + $1.value }, 1)
		var cumulative = 0.0
		return slices.enumerated().map { index, slice in
			let fraction = Double(slice.value) / Double(total)
			let start = Angle(degrees: cumulative * 360)
			cumulative += fraction
			let end = Angle(degrees: cumulative * 360)
			let color = Annotation.Color.allCases[index % Annotation.Color.allCases.count].swiftUIColor(palette: highlightPalette, isDark: isDark)
			return FandomWedge(id: index, name: slice.name, value: slice.value, color: color, start: start, end: end)
		}
	}

	var body: some View {
		let currentWedges = wedges
		let total = max(currentWedges.reduce(0) { $0 + $1.value }, 1)
		HStack(spacing: 16) {
			FandomPieChartView(wedges: currentWedges)
			FandomLegendView(wedges: currentWedges, total: total)
		}
	}

	private struct FandomPieChartView: View {
		let wedges: [FandomWedge]

		var body: some View {
			ZStack {
				ForEach(wedges) { wedge in
					PieSlice(startAngle: wedge.start, endAngle: wedge.end).fill(wedge.color)
				}
			}
			.frame(width: 110, height: 110)
		}
	}

	private struct FandomLegendView: View {
		let wedges: [FandomWedge]
		let total: Int

		var body: some View {
			VStack(alignment: .leading, spacing: 8) {
				ForEach(wedges) { wedge in
					FandomLegendRow(wedge: wedge, total: total)
				}
			}
		}
	}

	private struct FandomLegendRow: View {
		let wedge: FandomWedge
		let total: Int

		private var percent: Int {
			Int((Double(wedge.value) / Double(total) * 100).rounded())
		}

		var body: some View {
			HStack(spacing: 8) {
				Circle().fill(wedge.color).frame(width: 10, height: 10)
				Text(wedge.name)
					.font(.footnote)
					.foregroundStyle(.primary)
					.lineLimit(2)
					.layoutPriority(1)
				Spacer(minLength: 8)
				Text("\(percent)%")
					.font(.footnote)
					.foregroundStyle(.secondary)
					.monospacedDigit()
					.fixedSize()
			}
		}
	}
}

private struct ReadingStatsTagBarsView: View {
	let tags: [(name: String, value: Int)]
	let statsMetric: StatsMetric

	var body: some View {
		VStack(spacing: 10) {
			ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
				HStack {
					Text(tag.name)
						.font(.footnote)
						.foregroundStyle(.primary)
						.lineLimit(2)
					Spacer(minLength: 8)
					Text(statsMetric == .works ? "\(tag.value) works" : "\(tag.value)")
						.font(.footnote)
						.foregroundStyle(.secondary)
						.monospacedDigit()
						.fixedSize()
				}
			}
		}
	}
}
