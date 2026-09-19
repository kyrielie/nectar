//
//  ReadingInsightPlatterView.swift
//  Nectar
//
//  Rounded card container for Reading Stats' Streaks and Monthly sections.
//  Ported from Aidoku (https://github.com/Aidoku/Aidoku)'s
//  `Aidoku/Features/Settings/Insights/InsightPlatterView.swift`,
//  Copyright (c) the Aidoku authors (that file's header credits Skitty),
//  licensed under GPL-3.0 (see the LICENSE file at the root of that
//  repository). This file is therefore itself GPL-3.0-licensed -- see
//  THIRD-PARTY-NOTICES.md for the full notice.
//
//  Unchanged apart from the type name.
//

import SwiftUI

struct ReadingInsightPlatterView<Content: View>: View {
	@ViewBuilder var content: Content

	private let cornerRadius: CGFloat = 12

	var body: some View {
		content
			.background(
				RoundedRectangle(cornerRadius: cornerRadius)
					.fill(Color(uiColor: .secondarySystemGroupedBackground))
			)
			.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
			.shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 2)
	}
}
