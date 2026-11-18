//
//  ShareEPUBActivity.swift
//  Nectar
//
//  Custom UIActivity that exports the current work as a Standard Ebooks & AO3
//  compliant EPUB 3.3 book, presenting the system share sheet (AirDrop, Books, Kindle, Files).
//

import UIKit
import Articles
import Account

final class ShareEPUBActivity: UIActivity, @unchecked Sendable {

	private let article: Article?
	private let account: Account?
	private weak var presentingViewController: UIViewController?

	init(article: Article?, account: Account?, presentingViewController: UIViewController? = nil) {
		self.article = article
		self.account = account
		self.presentingViewController = presentingViewController
		super.init()
	}

	override var activityTitle: String? {
		return NSLocalizedString("Export as EPUB", comment: "Export work as EPUB file")
	}

	override var activityImage: UIImage? {
		return UIImage(systemName: "book.pages", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
	}

	override var activityType: UIActivity.ActivityType? {
		return UIActivity.ActivityType(rawValue: "com.kyrielie.Nectar.exportEPUB")
	}

	override static var activityCategory: UIActivity.Category {
		return .action
	}

	override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
		return article != nil
	}

	override func prepare(withActivityItems activityItems: [Any]) {
		// Target article and account captured at init time
	}

	override func perform() {
		MainActor.assumeIsolated {
			performOnMainActor()
		}
	}

	@MainActor
	private func performOnMainActor() {
		guard let article else {
			activityDidFinish(false)
			return
		}

		Task {
			let presenter = self.presentingViewController ?? UIApplication.shared.topMostViewController
			do {
				let epubURL = try await EPUB3Generator.generateEPUB(for: article, account: account)
				self.activityDidFinish(true)

				let shareVC = UIActivityViewController(activityItems: [epubURL], applicationActivities: nil)
				if let popover = shareVC.popoverPresentationController, let presenter {
					popover.sourceView = presenter.view
					popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
					popover.permittedArrowDirections = []
				}
				presenter?.present(shareVC, animated: true)
			} catch {
				self.activityDidFinish(false)
				let alert = UIAlertController(
					title: NSLocalizedString("EPUB Export Failed", comment: "Alert title"),
					message: error.localizedDescription,
					preferredStyle: .alert
				)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Dismiss button"), style: .default))
				presenter?.present(alert, animated: true)
			}
		}
	}
}

private extension UIApplication {
	var topMostViewController: UIViewController? {
		let keyWindow = connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap { $0.windows }
			.first { $0.isKeyWindow }

		var top = keyWindow?.rootViewController
		while let presented = top?.presentedViewController {
			top = presented
		}
		return top
	}
}
