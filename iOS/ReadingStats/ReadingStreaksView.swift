//
//  ReadingStreaksView.swift
//  Nectar
//
//  Current/longest streak platters plus the activity heatmap, for Reading
//  Stats' Streaks section. Ported from the streaks block of Aidoku
//  (https://github.com/Aidoku/Aidoku)'s
//  `Aidoku/Features/Settings/Insights/InsightsView.swift`, Copyright (c)
//  the Aidoku authors (that file's header credits Skitty), licensed under
//  GPL-3.0 (see the LICENSE file at the root of that repository). This
//  file is therefore itself GPL-3.0-licensed -- see THIRD-PARTY-NOTICES.md
//  for the full notice.
//
//  Layout, sizes and the show/hide rules for the platters are unchanged.
//  Aidoku's "STREAKS" section header is left to this app's List section
//  header, and its `NSLocalizedString` keys are replaced by this app's
//  source-text string-catalog keys.
//

import Account
import SwiftUI

struct ReadingStreaksView: View {
	let currentStreak: Int
	let longestStreak: Int
	let heatmapData: ReadingHeatmapData

	var body: some View {
		VStack(spacing: 8) {
			HStack(spacing: 8) {
				ReadingInsightPlatterView {
					Group {
						if currentStreak > 1 {
							VStack(spacing: 0) {
								Text("Current streak")
									.font(.system(size: 14))
								VStack(spacing: -5) {
									Text(currentStreak, format: .number.notation(.compactName))
										.font(.system(size: 38).weight(.bold))
									Text("Days")
										.font(.body.weight(.semibold))
										.multilineTextAlignment(.center)
								}
							}
						} else {
							VStack(spacing: 4) {
								Text("No current streak")
									.font(.headline)
								Text("Read every day to build a streak.")
									.font(.subheadline)
									.multilineTextAlignment(.center)
							}
						}
					}
					.padding(12)
					.frame(height: 110)
					.frame(maxWidth: .infinity)
				}

				if longestStreak > currentStreak && longestStreak > 1 {
					ReadingInsightPlatterView {
						VStack(spacing: 0) {
							Text("Longest streak")
								.font(.system(size: 14))
							VStack(spacing: -5) {
								Text(longestStreak, format: .number.notation(.compactName))
									.font(.system(size: 38).weight(.bold))
								Text("Days")
									.font(.body.weight(.semibold))
									.multilineTextAlignment(.center)
							}
						}
						.padding(12)
						.frame(height: 110)
						.frame(maxWidth: .infinity)
					}
				}
			}

			ReadingInsightPlatterView {
				HStack(spacing: 0) {
					LinearGradient(
						gradient: Gradient(
							colors: [
								Color(UIColor.secondarySystemGroupedBackground),
								Color(UIColor.secondarySystemGroupedBackground).opacity(0)
							]
						),
						startPoint: .leading,
						endPoint: .trailing
					)
					.flipsForRightToLeftLayoutDirection(true)
					.frame(width: 12)
					.zIndex(1)

					ReadingHeatmapView(data: heatmapData)
						.padding(.vertical, 12)
						.zIndex(0)

					LinearGradient(
						gradient: Gradient(
							colors: [
								Color(UIColor.secondarySystemGroupedBackground).opacity(0),
								Color(UIColor.secondarySystemGroupedBackground)
							]
						),
						startPoint: .leading,
						endPoint: .trailing
					)
					.flipsForRightToLeftLayoutDirection(true)
					.frame(width: 12)
					.zIndex(1)
				}
			}
		}
	}
}

#Preview {
	let (totalDays, startDate) = ReadingHeatmapData.daysAndStartDate(asOf: Date(), calendar: .current)
	let values = (0..<totalDays).map { $0 % 4 == 0 ? 0 : ($0 * 37) % 9_000 }
	return ReadingStreaksView(currentStreak: 4, longestStreak: 9, heatmapData: ReadingHeatmapData(startDate: startDate, values: values))
		.padding()
}
