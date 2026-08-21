//
//  FeedInspectorViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 11/6/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import SafariServices
import UserNotifications
import RSCore
import Account
import Images

final class FeedInspectorViewController: UITableViewController {

	static let preferredContentSizeForFormSheetDisplay = CGSize(width: 460.0, height: 500.0)

	var feed: Feed!

	@IBOutlet var nameTextField: UITextField!
	@IBOutlet var newArticleNotificationsEnabledSwitch: UISwitch!
	@IBOutlet var homePageLabel: UILabel!
	@IBOutlet var feedURLLabel: UILabel!

	private var headerView: InspectorIconHeaderView?
	private var iconImage: IconImage? {
		return IconImageCache.shared.imageForFeed(feed)
	}

	private let homePageIndexPath = IndexPath(row: 0, section: 1)
	private let feedURLIndexPath = IndexPath(row: 0, section: 2)

	private var shouldHideHomePageSection: Bool {
		return feed.homePageURL == nil
	}

	private var authorizationStatus: UNAuthorizationStatus?

	// MARK: - AO3 Pages (see docs/ao3-arbitrary-page-fetch.md)

	/// This section is appended in code after every storyboard section,
	/// rather than living in the storyboard itself -- `Inspector.storyboard`
	/// is static-cell Interface Builder content, and there's no safe way
	/// to hand-author a new IB scene fragment (object IDs, Auto Layout
	/// constraints, outlet connections) outside Xcode without real risk of
	/// a corrupt or silently-broken storyboard. `numberOfSections`/`shift`
	/// below still handle the existing storyboard sections exactly as
	/// before; this section is deliberately kept outside that shifting
	/// scheme, always the last section, present only for an AO3
	/// search-results feed.
	private var isAO3SearchResultsFeed: Bool {
		feed.isAO3SearchResultsFeed
	}

	private var ao3PagesSectionIndex: Int {
		// One past every storyboard section, already collapsed for
		// shouldHideHomePageSection -- same count numberOfSections(in:)
		// itself returns before this section is added on top of it.
		super.numberOfSections(in: tableView) - (shouldHideHomePageSection ? 1 : 0)
	}

	private var ao3PagesCell: AO3PagesInspectorCell?
	private var isAO3FetchInFlight = false

	override func viewDidLoad() {
		tableView.register(InspectorIconHeaderView.self, forHeaderFooterViewReuseIdentifier: "SectionHeader")
		tableView.register(AO3PagesInspectorCell.self, forCellReuseIdentifier: AO3PagesInspectorCell.reuseIdentifier)

		navigationItem.title = feed.nameForDisplay
		nameTextField.text = feed.nameForDisplay

		newArticleNotificationsEnabledSwitch.setOn(feed.newArticleNotificationsEnabled, animated: false)

		homePageLabel.text = feed.homePageURL
		feedURLLabel.text = feed.url

		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(updateNotificationSettings), name: UIApplication.willEnterForegroundNotification, object: nil)

		if isAO3SearchResultsFeed {
			NotificationCenter.default.addObserver(self, selector: #selector(feedSettingDidChange(_:)), name: .feedSettingDidChange, object: feed)
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		updateNotificationSettings()
	}

	override func viewDidDisappear(_ animated: Bool) {
		if nameTextField.text != feed.nameForDisplay {
			let nameText = nameTextField.text ?? ""
			let newName = nameText.isEmpty ? (feed.name ?? NSLocalizedString("Untitled", comment: "Feed name")) : nameText
			feed.rename(to: newName) { _ in }
		}
	}

	// MARK: Notifications
	@objc func feedIconDidBecomeAvailable(_ notification: Notification) {
		headerView?.iconView.iconImage = iconImage
	}

	@IBAction func newArticleNotificationsEnabledChanged(_ sender: Any) {
		guard let authorizationStatus else {
			newArticleNotificationsEnabledSwitch.isOn = !newArticleNotificationsEnabledSwitch.isOn
			return
		}
		if authorizationStatus == .denied {
			newArticleNotificationsEnabledSwitch.isOn = !newArticleNotificationsEnabledSwitch.isOn
			present(notificationUpdateErrorAlert(), animated: true, completion: nil)
		} else if authorizationStatus == .authorized {
			feed.newArticleNotificationsEnabled = newArticleNotificationsEnabledSwitch.isOn
		} else {
			UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { granted, _ in
				Task { @MainActor in
					self.updateNotificationSettings()
					if granted {
						self.feed.newArticleNotificationsEnabled = self.newArticleNotificationsEnabledSwitch.isOn
						UIApplication.shared.registerForRemoteNotifications()
					} else {
						self.newArticleNotificationsEnabledSwitch.isOn = !self.newArticleNotificationsEnabledSwitch.isOn
					}
				}
			}
		}
	}

	@IBAction func done(_ sender: Any) {
		dismiss(animated: true)
	}

	/// Returns a new indexPath, taking into consideration any
	/// conditions that may require the tableView to be
	/// displayed differently than what is setup in the storyboard.
	private func shift(_ indexPath: IndexPath) -> IndexPath {
		return IndexPath(row: indexPath.row, section: shift(indexPath.section))
	}

	/// Returns a new section, taking into consideration any
	/// conditions that may require the tableView to be
	/// displayed differently than what is setup in the storyboard.
	private func shift(_ section: Int) -> Int {
		if section >= homePageIndexPath.section && shouldHideHomePageSection {
			return section + 1
		}
		return section
	}
}

// MARK: Table View

extension FeedInspectorViewController {

	override func numberOfSections(in tableView: UITableView) -> Int {
		let numberOfSections = super.numberOfSections(in: tableView)
		let visibleStoryboardSections = shouldHideHomePageSection ? numberOfSections - 1 : numberOfSections
		return visibleStoryboardSections + (isAO3SearchResultsFeed ? 1 : 0)
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		guard section != ao3PagesSectionIndex else { return 1 }
		return super.tableView(tableView, numberOfRowsInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		guard section != ao3PagesSectionIndex else {
			return super.tableView(tableView, heightForHeaderInSection: 0) // storyboard's default section-header height, not the icon header's
		}
		return section == 0 ? ImageHeaderView.rowHeight : super.tableView(tableView, heightForHeaderInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard indexPath.section != ao3PagesSectionIndex else {
			let cell = tableView.dequeueReusableCell(withIdentifier: AO3PagesInspectorCell.reuseIdentifier, for: indexPath) as! AO3PagesInspectorCell
			cell.configure(feed: feed, isFetchInFlight: isAO3FetchInFlight) { [weak self] page in
				self?.fetchAO3Page(page)
			}
			ao3PagesCell = cell
			return cell
		}
		let cell = super.tableView(tableView, cellForRowAt: shift(indexPath))
		if indexPath.section == 0 && indexPath.row == 1 {
			guard let label = cell.contentView.subviews.filter({ $0.isKind(of: UILabel.self) })[0] as? UILabel else {
				return cell
			}
			label.numberOfLines = 2
			label.text = feed.notificationDisplayName.capitalized
		}
		return cell
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		guard section != ao3PagesSectionIndex else {
			return NSLocalizedString("AO3 Pages", comment: "AO3 arbitrary-page-fetch inspector section header")
		}
		return super.tableView(tableView, titleForHeaderInSection: shift(section))
	}

	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		if section == ao3PagesSectionIndex {
			return nil // falls back to titleForHeaderInSection's plain text header
		} else if shift(section) == 0 {
			headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SectionHeader") as? InspectorIconHeaderView
			headerView?.iconView.iconImage = iconImage
			return headerView
		} else {
			return super.tableView(tableView, viewForHeaderInSection: shift(section))
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		guard indexPath.section != ao3PagesSectionIndex else { return }
		if shift(indexPath) == homePageIndexPath,
			let homePageUrlString = feed.homePageURL,
			let homePageUrl = URL(string: homePageUrlString) {

			let safari = SFSafariViewController(url: homePageUrl)
			safari.modalPresentationStyle = .pageSheet
			present(safari, animated: true) {
				tableView.deselectRow(at: indexPath, animated: true)
			}
		}
	}

	override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
		guard indexPath.section != ao3PagesSectionIndex else { return nil }
		let logicalIndexPath = shift(indexPath)
		let title: String
		let urlString: String?
		if logicalIndexPath == homePageIndexPath {
			title = NSLocalizedString("Copy Home Page URL", comment: "Command")
			urlString = feed.homePageURL
		} else if logicalIndexPath == feedURLIndexPath {
			title = NSLocalizedString("Copy Feed URL", comment: "Command")
			urlString = feed.url
		} else {
			return nil
		}
		guard let urlString else {
			return nil
		}
		return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
			let copyAction = UIAction(title: title, image: Assets.Images.copy) { _ in
				UIPasteboard.general.string = urlString
			}
			return UIMenu(title: "", children: [copyAction])
		}
	}

}

// MARK: - AO3 Pages

private extension FeedInspectorViewController {

	@objc func feedSettingDidChange(_ notification: Notification) {
		guard let key = notification.userInfo?[Feed.SettingUserInfoKey] as? Feed.SettingKey else { return }
		guard key == .ao3SearchFetchedPages || key == .ao3SearchTotalPages else { return }
		ao3PagesCell?.configure(feed: feed, isFetchInFlight: isAO3FetchInFlight) { [weak self] page in
			self?.fetchAO3Page(page)
		}
	}

	/// Part 3's validation flow, run against the paginator's own
	/// `validate(page:against:)` before spending a network request on an
	/// already-known-out-of-range page; `fetchSpecificPage` itself
	/// re-validates once more internally for the case where
	/// `ao3SearchTotalPages` wasn't known yet and had to be populated by
	/// an intervening page-1 fetch (see that function's own doc comment).
	func fetchAO3Page(_ page: Int) {
		guard !isAO3FetchInFlight else { return }
		guard let account = feed.account else {
			ao3PagesCell?.showValidationError(NSLocalizedString("This feed's account is unavailable", comment: "AO3 arbitrary-page-fetch: missing account"))
			return
		}

		ao3PagesCell?.clearErrorForNewAttempt()

		if case .outOfRange(let totalPages) = AO3SearchResultsPaginator.validate(page: page, against: feed) {
			ao3PagesCell?.showValidationError(String(format: NSLocalizedString("AO3 reports %d pages for this search.", comment: "AO3 arbitrary-page-fetch: page out of range"), totalPages))
			return
		}

		isAO3FetchInFlight = true
		ao3PagesCell?.configure(feed: feed, isFetchInFlight: true) { [weak self] page in
			self?.fetchAO3Page(page)
		}

		Task { @MainActor [weak self] in
			guard let self else { return }
			let outcome = await AO3SearchResultsPaginator.fetchSpecificPage(page, for: self.feed, account: account)
			self.isAO3FetchInFlight = false

			switch outcome {
			case .loaded, .noResults:
				break // feed.ao3SearchFetchedPages/.ao3SearchTotalPages already updated by the paginator; feedSettingDidChange refreshes the cell.
			case .registrationRequired:
				self.ao3PagesCell?.showValidationError(NSLocalizedString("Restricted to registered AO3 users", comment: "AO3 load more error"))
			case .rateLimited:
				self.ao3PagesCell?.showValidationError(NSLocalizedString("AO3 rate limit hit -- backing off before retrying", comment: "AO3 load more error"))
			case .cloudflareChallenge(let challengedURL):
				self.presentAO3FetchVerificationPrompt(challengedURL: challengedURL, page: page, account: account)
			case .notSignedIn:
				self.ao3PagesCell?.showValidationError(NSLocalizedString("This feed requires a signed-in AO3 account", comment: "AO3 load more error"))
			}

			self.ao3PagesCell?.configure(feed: self.feed, isFetchInFlight: self.isAO3FetchInFlight) { [weak self] page in
				self?.fetchAO3Page(page)
			}
		}
	}

	/// Same opt-in Cloudflare-verification alert pattern as the existing
	/// load-more UI (`MainTimelineModernViewController.presentAO3LoadMoreVerificationPrompt`)
	/// -- never presents the WKWebView solver automatically. `updatesFeedName: false`
	/// per Part 4: this retry is never the create-time add, so it must
	/// never rename an already-named feed.
	func presentAO3FetchVerificationPrompt(challengedURL: URL, page: Int, account: Account) {
		let alert = UIAlertController(
			title: NSLocalizedString("AO3 Needs Verification", comment: "AO3 Cloudflare challenge prompt title"),
			message: NSLocalizedString("AO3 needs you to verify you're not a bot before this page can load. Verify now?", comment: "AO3 Cloudflare challenge prompt message"),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("Not Now", comment: "Decline AO3 verification"), style: .cancel) { [weak self] _ in
			guard let self else { return }
			self.isAO3FetchInFlight = false
			self.ao3PagesCell?.configure(feed: self.feed, isFetchInFlight: false) { [weak self] page in
				self?.fetchAO3Page(page)
			}
		})
		alert.addAction(UIAlertAction(title: NSLocalizedString("Verify", comment: "Accept AO3 verification"), style: .default) { [weak self] _ in
			guard let self else { return }
			self.isAO3FetchInFlight = true
			self.ao3PagesCell?.configure(feed: self.feed, isFetchInFlight: true) { [weak self] page in
				self?.fetchAO3Page(page)
			}
			Task { @MainActor in
				let coordinator = AO3SearchResultsFetchCoordinator()
				let outcome = await coordinator.presentSolverAndRetry(challengedURL: challengedURL, feedURL: self.feed.url, feed: self.feed, account: account, advancePageTo: page, updatesFeedName: false, presentingViewController: self)
				self.isAO3FetchInFlight = false
				switch outcome {
				case .imported, .noResults:
					break
				case .registrationRequired:
					self.ao3PagesCell?.showValidationError(NSLocalizedString("Restricted to registered AO3 users", comment: "AO3 load more error"))
				case .rateLimited:
					self.ao3PagesCell?.showValidationError(NSLocalizedString("AO3 rate limit hit -- backing off before retrying", comment: "AO3 load more error"))
				case .needsVerification, .cancelled:
					break
				case .failed(let message):
					self.ao3PagesCell?.showValidationError(message)
				case .notSignedIn:
					self.ao3PagesCell?.showValidationError(NSLocalizedString("This feed requires a signed-in AO3 account", comment: "AO3 load more error"))
				}
				self.ao3PagesCell?.configure(feed: self.feed, isFetchInFlight: self.isAO3FetchInFlight) { [weak self] page in
					self?.fetchAO3Page(page)
				}
			}
		})
		present(alert, animated: true)
	}
}

// MARK: UITextFieldDelegate

extension FeedInspectorViewController: UITextFieldDelegate {

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}

}

// MARK: UNUserNotificationCenter

extension FeedInspectorViewController {

	@objc func updateNotificationSettings() {
		UNUserNotificationCenter.current().getNotificationSettings { (settings) in
			let updatedAuthorizationStatus = settings.authorizationStatus
			DispatchQueue.main.async {
				self.authorizationStatus = updatedAuthorizationStatus
				if self.authorizationStatus == .authorized {
					UIApplication.shared.registerForRemoteNotifications()
				}
			}
		}
	}

	func notificationUpdateErrorAlert() -> UIAlertController {
		let alert = UIAlertController(title: NSLocalizedString("Enable Notifications", comment: "Notifications"),
									  message: NSLocalizedString("Notifications need to be enabled in the Settings app.", comment: "Notifications need to be enabled in the Settings app."), preferredStyle: .alert)
		let openSettings = UIAlertAction(title: NSLocalizedString("Open Settings", comment: "Open Settings button"), style: .default) { _ in
			UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [UIApplication.OpenExternalURLOptionsKey.universalLinksOnly: false], completionHandler: nil)
		}
		let dismiss = UIAlertAction(title: NSLocalizedString("Dismiss", comment: "Dismiss"), style: .cancel, handler: nil)
		alert.addAction(openSettings)
		alert.addAction(dismiss)
		alert.preferredAction = openSettings
		return alert
	}

}

// MARK: - AO3PagesInspectorCell

/// Part 7's mockup, as one self-contained cell:
///
///     Fetched: 1, 2, 3, 7  (12 pages total)
///
///     Fetch a page:  [   4   ]  [ Fetch ]
///
///     (i) Fetched pages are additive -- refetching a
///         page adds any new works, never removes any.
///
/// "(N pages total)" only appears once `feed.ao3SearchTotalPages` is
/// known. Numeric-keyboard text field, Fetch button disabled until the
/// typed text parses as a positive integer, spinner-in-button while a
/// fetch is in flight. Tappable "already fetched" page numbers for
/// one-tap refetch are deferred (Part 7) -- type-a-number-and-tap-Fetch
/// only, for this first pass.
private final class AO3PagesInspectorCell: VibrantTableViewCell {

	static let reuseIdentifier = "AO3PagesInspectorCell"

	private let fetchedLabel = UILabel()
	private let pageTextField = UITextField()
	private let fetchButton = VibrantButton(type: .system)
	private let spinner = UIActivityIndicatorView(style: .medium)
	private let errorLabel = UILabel()
	private let noteLabel = UILabel()

	private var onFetchTapped: ((Int) -> Void)?

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		selectionStyle = .none
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		selectionStyle = .none
		commonInit()
	}

	private func commonInit() {
		fetchedLabel.font = .preferredFont(forTextStyle: .subheadline)
		fetchedLabel.textColor = .secondaryLabel
		fetchedLabel.numberOfLines = 0

		pageTextField.borderStyle = .roundedRect
		pageTextField.keyboardType = .numberPad
		pageTextField.textAlignment = .center
		pageTextField.placeholder = NSLocalizedString("Page", comment: "AO3 arbitrary-page-fetch: page number field placeholder")
		pageTextField.addTarget(self, action: #selector(pageTextDidChange), for: .editingChanged)
		pageTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)

		fetchButton.setTitle(NSLocalizedString("Fetch", comment: "AO3 arbitrary-page-fetch: fetch button"), for: .normal)
		fetchButton.addTarget(self, action: #selector(fetchTapped), for: .touchUpInside)
		fetchButton.isEnabled = false
		fetchButton.setContentHuggingPriority(.required, for: .horizontal)

		spinner.hidesWhenStopped = true

		errorLabel.font = .preferredFont(forTextStyle: .footnote)
		errorLabel.textColor = .systemRed
		errorLabel.numberOfLines = 0
		errorLabel.isHidden = true

		noteLabel.font = .preferredFont(forTextStyle: .caption1)
		noteLabel.textColor = .secondaryLabel
		noteLabel.numberOfLines = 0
		noteLabel.text = NSLocalizedString("Fetched pages are additive -- refetching a page adds any new works, never removes any.", comment: "AO3 arbitrary-page-fetch: additive note")

		let fetchRow = UIStackView(arrangedSubviews: [pageTextField, fetchButton, spinner])
		fetchRow.axis = .horizontal
		fetchRow.spacing = 8
		fetchRow.alignment = .center

		let stack = UIStackView(arrangedSubviews: [fetchedLabel, fetchRow, errorLabel, noteLabel])
		stack.axis = .vertical
		stack.spacing = 8
		stack.translatesAutoresizingMaskIntoConstraints = false

		contentView.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
			stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 4),
			stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor, constant: -4),
			pageTextField.widthAnchor.constraint(equalToConstant: 60)
		])
	}

	func configure(feed: Feed?, isFetchInFlight: Bool, onFetchTapped: @escaping (Int) -> Void) {
		self.onFetchTapped = onFetchTapped

		let fetchedPages = (feed?.ao3SearchFetchedPages ?? []).sorted()
		let fetchedText = fetchedPages.isEmpty
			? NSLocalizedString("Fetched: none yet", comment: "AO3 arbitrary-page-fetch: no pages fetched")
			: String(format: NSLocalizedString("Fetched: %@", comment: "AO3 arbitrary-page-fetch: fetched-pages list"), fetchedPages.map(String.init).joined(separator: ", "))

		if let totalPages = feed?.ao3SearchTotalPages {
			fetchedLabel.text = fetchedText + " " + String(format: NSLocalizedString("(%d pages total)", comment: "AO3 arbitrary-page-fetch: total page count qualifier"), totalPages)
		} else {
			fetchedLabel.text = fetchedText
		}

		// Deliberately does NOT clear errorLabel -- showValidationError(_:)
		// is always called (if at all) before the configure(...) that
		// follows a fetch attempt's outcome, and clearing here would erase
		// the message this same call sequence just set. clearErrorForNewAttempt()
		// is the explicit way to clear it, called only when a fresh
		// attempt actually starts.

		pageTextField.isEnabled = !isFetchInFlight
		spinner.isHidden = !isFetchInFlight
		if isFetchInFlight {
			spinner.startAnimating()
		} else {
			spinner.stopAnimating()
		}
		fetchButton.isHidden = isFetchInFlight
		updateFetchButtonEnabled()
	}

	/// Shown for a validation failure (out-of-range page) or a fetch
	/// error (rate-limited, registration-required, Cloudflare, etc) --
	/// reuses the same message strings the "load more" footer already
	/// produces for the shared failure cases (see `AO3LoadMoreFooterView`'s
	/// own doc comment), deliberately not writing new copy for the same
	/// underlying failures.
	func showValidationError(_ message: String) {
		errorLabel.text = message
		errorLabel.isHidden = false
	}

	/// Called at the start of a fresh fetch attempt (typing after a
	/// previous failure, or tapping Fetch again) -- the only place a
	/// shown error is cleared, so `configure(feed:isFetchInFlight:onFetchTapped:)`
	/// itself never clobbers a message a caller just set.
	func clearErrorForNewAttempt() {
		errorLabel.isHidden = true
		errorLabel.text = nil
	}

	@objc private func pageTextDidChange() {
		clearErrorForNewAttempt()
		updateFetchButtonEnabled()
	}

	private func updateFetchButtonEnabled() {
		fetchButton.isEnabled = typedPage != nil && spinner.isAnimating == false
	}

	private var typedPage: Int? {
		guard let text = pageTextField.text, let page = Int(text), page > 0 else {
			return nil
		}
		return page
	}

	@objc private func fetchTapped() {
		guard let page = typedPage else { return }
		pageTextField.resignFirstResponder()
		onFetchTapped?(page)
	}
}
