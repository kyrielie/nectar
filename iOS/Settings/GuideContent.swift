//
//  GuideContent.swift
//  NetNewsWire-iOS
//
//  Static, hand-maintained content for GuideOverlayView -- there is no
//  backend/CMS for this anywhere in the codebase (confirmed), matching
//  how the removed AO3 onboarding's own copy was hardcoded. Append a new
//  GuidePage in the same PR that ships whatever that page is introducing,
//  so the Guide never lags behind the feature it's describing.
//
//  No "seen"/"unseen" tracking exists against this list (a `pages.last`
//  comparison was considered and explicitly dropped for this pass -- see
//  docs/guide.md). Adding a page here does not, on its own, draw any
//  attention back to the Settings row that opens it.
//

import Foundation

struct GuidePage: Identifiable {
	let id: String
	let title: String
	let body: String
}

enum GuideContent {
	static let pages: [GuidePage] = [
		GuidePage(
			id: "annotations-intro",
			title: "Annotations",
			body: "Highlight a line, add a note, and it stays put across re-reads. Tap and hold any text to get started."
		),
		GuidePage(
			id: "text-replacement-intro",
			title: "Text Replacement",
			body: "Typos in a fic bugging you? Set up a rule once and Nectar quietly fixes it everywhere, every time."
		),
		GuidePage(
			id: "screen-time-intro",
			title: "Screen Time",
			body: "Set a daily reading limit or a bedtime window. Nectar will gently lock you out when it's time to sleep."
		)
	]
}
