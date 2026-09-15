//
//  FolderPickerView.swift
//  Nectar
//
//  SwiftUI bridge onto AddFeedFolderViewController -- the nesting-aware
//  UIKit folder picker Add Feed uses (see AddFeedFolderViewController.swift's
//  own doc comment on its Row/depth walk). Kept as a thin
//  UIViewControllerRepresentable wrapper rather than a second, SwiftUI-native
//  picker, so every feed-adding flow (Add Feed today, Import AO3 Links once
//  its own destination-picker UI lands) shares one nesting-aware
//  implementation instead of two that could drift apart -- same reasoning as
//  Container.sortedFolders being hoisted for this same change.
//

import SwiftUI
import Account

struct FolderPickerView: UIViewControllerRepresentable {

	var initialContainer: Container?
	var accountFilter: Account?
	var onSelect: (Container) -> Void

	func makeUIViewController(context: Context) -> UINavigationController {
		let navController = UIStoryboard.add.instantiateViewController(withIdentifier: "AddFeedFolderNavViewController") as! UINavigationController
		let folderViewController = navController.topViewController as! AddFeedFolderViewController
		folderViewController.delegate = context.coordinator
		folderViewController.initialContainer = initialContainer
		folderViewController.accountFilter = accountFilter
		return navController
	}

	// initialContainer/onSelect are read once at presentation time
	// (makeUIViewController), matching AddFeedViewController's own
	// one-shot wiring of the same view controller -- nothing here needs
	// to react to a SwiftUI state change after the picker is already on
	// screen.
	func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(onSelect: onSelect)
	}

	@MainActor final class Coordinator: AddFeedFolderViewControllerDelegate {
		let onSelect: (Container) -> Void

		init(onSelect: @escaping (Container) -> Void) {
			self.onSelect = onSelect
		}

		func didSelect(container: Container) {
			onSelect(container)
		}
	}
}
