//
//  RefreshProgressView.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 10/24/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import Account

final class RefreshProgressView: UIView {

	private let progressView = UIProgressView(progressViewStyle: .default)
	private let label = UILabel()

	override init(frame: CGRect) {
		super.init(frame: frame)
		setup()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setup()
	}

	func update() {
		if !CombinedRefreshProgress.shared.isComplete {
			progressChanged(animated: false)
		} else {
			updateRefreshLabel()
		}
	}

	override func didMoveToSuperview() {
		progressChanged(animated: false)
	}

	@objc func progressInfoDidChange(_ note: Notification) {
		progressChanged(animated: true)
	}

	@objc func contentSizeCategoryDidChange(_ note: Notification) {
		label.font = UIFont.preferredFont(forTextStyle: .footnote)
	}

	nonisolated @objc func userDefaultsDidChange(_ note: Notification) {
		// NotificationCenter doesn't guarantee this fires on the main
		// thread -- UserDefaults.didChangeNotification can be posted from
		// a background thread (observed during XCTest's own bootstrap).
		// Hop to the main actor explicitly rather than asserting
		// isolation synchronously at this @objc entry point.
		Task { @MainActor in
			// Only the "Updated X ago" text is gated by showLastUpdatedLabel; the
			// progress bar during an active refresh is a different signal and
			// isn't affected. Calling updateRefreshLabel() unconditionally here is
			// harmless when a refresh is in progress -- update() will overwrite
			// the label the next time progressChanged(animated:) completes.
			self.updateRefreshLabel()
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}

// MARK: Private

private extension RefreshProgressView {

	func setup() {
		progressView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(progressView)

		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = UIFont.preferredFont(forTextStyle: .footnote)
		label.textColor = .secondaryLabel
		label.textAlignment = .center
		label.adjustsFontForContentSizeCategory = true
		addSubview(label)

		NSLayoutConstraint.activate([
			progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
			progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
			progressView.centerYAnchor.constraint(equalTo: centerYAnchor),

			label.leadingAnchor.constraint(equalTo: leadingAnchor),
			label.trailingAnchor.constraint(equalTo: trailingAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor)
		])

		NotificationCenter.default.addObserver(self, selector: #selector(progressInfoDidChange(_:)), name: .progressInfoDidChange, object: CombinedRefreshProgress.shared)
		NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange(_:)), name: UIContentSizeCategory.didChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange(_:)), name: UserDefaults.didChangeNotification, object: nil)

		update()
		scheduleUpdateRefreshLabel()

		isAccessibilityElement = true
		accessibilityTraits = [.updatesFrequently, .notEnabled]
	}

	func progressChanged(animated: Bool) {
		// Layout may crash if not in the view hierarchy.
		// https://github.com/Ranchero-Software/NetNewsWire/issues/1764
		let isInViewHierarchy = self.superview != nil

		let progressInfo = CombinedRefreshProgress.shared.progressInfo

		if progressInfo.isComplete {
			if isInViewHierarchy {
				progressView.setProgress(1, animated: animated)
			}

			func completeLabel() {
				// Check that there are no pending downloads.
				if CombinedRefreshProgress.shared.isComplete {
					self.updateRefreshLabel()
					self.label.isHidden = false
					self.progressView.isHidden = true
					if self.superview != nil {
						self.progressView.setProgress(0, animated: animated)
					}
				}
			}

			if animated {
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					completeLabel()
				}
			} else {
				completeLabel()
			}
		} else {
			label.isHidden = true
			progressView.isHidden = false
			if isInViewHierarchy {
				let percent = Float(progressInfo.numberCompleted) / Float(progressInfo.numberOfTasks)

				// Don't let the progress bar go backwards unless we need to go back more than 25%
				if percent > progressView.progress || progressView.progress - percent > 0.25 {
					progressView.setProgress(percent, animated: animated)
				}
			}
		}
	}

	func updateRefreshLabel() {
		guard AppDefaults.shared.showLastUpdatedLabel else {
			label.text = ""
			accessibilityLabel = nil
			return
		}

		if let accountLastArticleFetchEndTime = AccountManager.shared.lastRefreshCompletedDate {

			if Date() > accountLastArticleFetchEndTime.addingTimeInterval(60) {

				let relativeDateTimeFormatter = RelativeDateTimeFormatter()
				relativeDateTimeFormatter.dateTimeStyle = .named
				let refreshed = relativeDateTimeFormatter.localizedString(for: accountLastArticleFetchEndTime, relativeTo: Date())
				let localizedRefreshText = NSLocalizedString("Updated %@", comment: "Updated")
				let refreshText = NSString.localizedStringWithFormat(localizedRefreshText as NSString, refreshed) as String
				label.text = refreshText

			} else {
				label.text = NSLocalizedString("Updated Just Now", comment: "Updated Just Now")
			}

		} else {
			label.text = ""
		}

		accessibilityLabel = label.text
	}

	func scheduleUpdateRefreshLabel() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
			self?.updateRefreshLabel()
			self?.scheduleUpdateRefreshLabel()
		}
	}
}
