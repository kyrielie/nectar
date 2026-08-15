//
//  AO3OnboardingView.swift
//  NetNewsWire-iOS
//
//  Nectar AO3 direct-reading support: first-run onboarding, shown when a
//  fresh local account has no subscribed feeds yet. See
//  AppDefaults.shared.hasShownAO3Onboarding in docs/settings-screen.md.
//
//  Shown once, only when the local account has zero subscribed feeds (see
//  MainFeedCollectionViewController.presentAO3OnboardingIfNeeded()).
//  AddAccountViewController itself needs no changes for this -- there's no
//  new AccountType, just a hint seeded into the existing AddFeedViewController.
//

import SwiftUI

struct AO3OnboardingView: View {

	/// Called when "Add an AO3 Feed" is tapped -- the caller is
	/// responsible for dismissing this view and presenting
	/// AddFeedViewController (via SceneCoordinator.showAddFeed) seeded with
	/// an AO3 starting point.
	var onAddFeed: () -> Void

	/// Called when "Not Now" is tapped, or the screen is otherwise
	/// dismissed without adding a feed.
	var onSkip: () -> Void

	var body: some View {
		VStack(spacing: 20) {
			Spacer()

			Image(systemName: "book.pages")
				.font(.system(size: 56))
				.foregroundStyle(.secondary)

			Text(verbatim: "Read AO3 in Nectar")
				.font(.title2)
				.bold()

			Text("Follow a tag, a user, or a specific work on Archive of Our Own, and Nectar will pull in full chapter text as it's posted -- no ads, no extra taps out to the browser.")
				.multilineTextAlignment(.center)
				.foregroundStyle(.secondary)
				.padding(.horizontal, 32)

			Spacer()

			VStack(spacing: 12) {
				Button {
					onAddFeed()
				} label: {
					Text(NSLocalizedString("Add an AO3 Feed", comment: "AO3 onboarding primary action"))
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)

				Button {
					onSkip()
				} label: {
					Text(NSLocalizedString("Not Now", comment: "AO3 onboarding dismiss action"))
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)
			}
			.padding(.horizontal, 32)
			.padding(.bottom, 24)
		}
		.interactiveDismissDisabled(false)
	}
}

#Preview {
	AO3OnboardingView(onAddFeed: {}, onSkip: {})
}
