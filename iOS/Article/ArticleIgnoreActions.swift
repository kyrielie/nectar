//
//  ArticleIgnoreActions.swift
//  NetNewsWire
//
//  "Ignore This Work" and "Ignore Author" for the article that is open in the
//  reader. Shared by the reader's press-and-hold context menu
//  (WebViewController.ignoreActions()) and the toolbar's Ignore function
//  (ArticleViewController), so both offer the same rows, copy and confirmations.
//

import UIKit
import AO3Kit
import Articles

@MainActor
enum ArticleIgnoreActions {

	/// Whether `article` is a single AO3 work, the only kind the ignore rules apply
	/// to. Anything else gets no actions.
	static func isAvailable(for article: Article?) -> Bool {
		guard let article else {
			return false
		}
		return AO3FetchPolicy.workID(fromBookKey: article.bookKey) != nil
	}

	/// "Ignore This Work" and "Ignore Author" for an AO3 work; empty for anything else.
	/// Ignoring hides future feed items only (see `AO3IgnoreList`), so each action
	/// confirms, presenting from `presenter`. An author is offered only with an AO3 URL,
	/// since rules match by exact URL. With several authors, each gets a row named after
	/// them.
	static func actions(for article: Article?, presenter: UIViewController) -> [UIAction] {
		guard let article, let workID = AO3FetchPolicy.workID(fromBookKey: article.bookKey) else {
			return []
		}

		var actions = [UIAction]()
		let workTitle = article.title
		actions.append(UIAction(title: NSLocalizedString("Ignore This Work", comment: "Command: hide future feed items for this AO3 work"), image: UIImage(systemName: "eye.slash")) { [weak presenter] _ in
			guard let presenter else { return }
			confirmIgnoreWork(id: workID, title: workTitle, presenter: presenter)
		})

		let authorsWithURLs = (article.authors ?? [])
			.compactMap { author -> (url: String, name: String?)? in
				guard let urlString = author.url, let url = URL(string: urlString), AO3Link.isAO3Host(url) else {
					return nil
				}
				return (urlString, author.name)
			}
			.sorted { ($0.name ?? $0.url) < ($1.name ?? $1.url) }

		for author in authorsWithURLs {
			let title: String
			if authorsWithURLs.count > 1, let name = author.name, !name.isEmpty {
				title = String(format: NSLocalizedString("Ignore Author: %@", comment: "Command: hide future feed items by this AO3 author; %@ is the author's name"), name)
			} else {
				title = NSLocalizedString("Ignore Author", comment: "Command: hide future feed items by this AO3 author")
			}
			actions.append(UIAction(title: title, image: UIImage(systemName: "person.crop.circle.badge.xmark")) { [weak presenter] _ in
				guard let presenter else { return }
				confirmIgnoreAuthor(url: author.url, name: author.name, presenter: presenter)
			})
		}
		return actions
	}

	private static func confirmIgnoreWork(id: String, title: String?, presenter: UIViewController) {
		let message = NSLocalizedString("New feed items for this work will be hidden. It stays in your library, and you can undo this in AO3 settings under Ignored Works and Authors.", comment: "Ignore work confirmation message")
		let alert = UIAlertController(title: NSLocalizedString("Ignore This Work?", comment: "Ignore work confirmation title"), message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Ignore Work", comment: "Command"), style: .destructive) { _ in
			AO3IgnoreList.ignoreWork(id: id, label: title)
		})
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
		presenter.present(alert, animated: true)
	}

	private static func confirmIgnoreAuthor(url: String, name: String?, presenter: UIViewController) {
		let message = NSLocalizedString("New feed items by this author will be hidden. Their works already in your library stay, and you can undo this in AO3 settings under Ignored Works and Authors.", comment: "Ignore author confirmation message")
		let alert = UIAlertController(title: NSLocalizedString("Ignore This Author?", comment: "Ignore author confirmation title"), message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Ignore Author", comment: "Command"), style: .destructive) { _ in
			AO3IgnoreList.ignoreAuthor(url: url, label: name)
		})
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
		presenter.present(alert, animated: true)
	}
}
