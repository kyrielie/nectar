//
//  ManageStorageCollectionViewController.swift
//  NetNewsWire-iOS
//
//  Manual, size-sorted cleanup tool -- Instapaper/Pocket's "manage storage"
//  pattern, not NetNewsWire's own "expire unread articles after N days."
//  There is no automatic eviction of archived article content; deleting a
//  row here is the only way an article's stored contentHTML goes away. See
//  Task 5 of nectar-ao3-features-plan-FINAL.md.
//

import UIKit
import Account
import ArticlesDatabase

final class ManageStorageCollectionViewController: UICollectionViewController {

	private enum Item: Hashable {
		case summary
		case article(String) // articleID
	}

	private let viewModel = ManageStorageViewModel()
	private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!
	private var rowsByArticleID = [String: ManageStorageRowData]()

	init() {
		// Plain list layout here; trailingSwipeActionsConfigurationProvider
		// is wired up in configureCollectionView(), called from viewDidLoad,
		// so its closure can capture `self` normally (self doesn't exist
		// yet at this point in init) -- same split MainFeedCollectionViewController
		// uses for the same reason.
		let config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
		let layout = UICollectionViewCompositionalLayout.list(using: config)
		super.init(collectionViewLayout: layout)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Manage Storage", comment: "Manage Storage")

		configureCollectionView()
		configureDataSource()

		Task {
			await viewModel.refresh()
			applySnapshot()
		}
	}

	private func configureCollectionView() {
		var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
		config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
			self?.trailingSwipeActionsConfiguration(forRowAt: indexPath)
		}
		let layout = UICollectionViewCompositionalLayout.list(using: config)
		collectionView.setCollectionViewLayout(layout, animated: false)
	}

	// MARK: Data source

	private func configureDataSource() {
		let summaryCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [weak self] cell, _, _ in
			var content = cell.defaultContentConfiguration()
			content.text = NSLocalizedString("Total Storage Used", comment: "Manage Storage total row")
			content.secondaryText = self?.formattedSize(self?.viewModel.totalStoredContentHTMLSize ?? 0)
			cell.contentConfiguration = content
			cell.accessories = []
		}

		let articleCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [weak self] cell, _, item in
			guard case .article(let articleID) = item, let row = self?.rowsByArticleID[articleID] else {
				return
			}
			var content = cell.defaultContentConfiguration()
			content.text = row.title
			content.secondaryText = self?.formattedSize(row.storedContentHTMLSize)
			cell.contentConfiguration = content
			cell.accessories = []
		}

		dataSource = UICollectionViewDiffableDataSource<Int, Item>(collectionView: collectionView) { collectionView, indexPath, item in
			switch item {
			case .summary:
				return collectionView.dequeueConfiguredReusableCell(using: summaryCellRegistration, for: indexPath, item: item)
			case .article:
				return collectionView.dequeueConfiguredReusableCell(using: articleCellRegistration, for: indexPath, item: item)
			}
		}
	}

	private func applySnapshot() {
		rowsByArticleID = Dictionary(uniqueKeysWithValues: viewModel.rows.map { ($0.articleID, $0) })

		var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
		snapshot.appendSections([0, 1])
		snapshot.appendItems([.summary], toSection: 0)
		snapshot.appendItems(viewModel.rows.map { .article($0.articleID) }, toSection: 1)
		dataSource.apply(snapshot, animatingDifferences: true)
	}

	// MARK: Swipe to clear content

	private func trailingSwipeActionsConfiguration(forRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		guard let item = dataSource.itemIdentifier(for: indexPath),
			  case .article(let articleID) = item,
			  let row = rowsByArticleID[articleID] else {
			return UISwipeActionsConfiguration(actions: [])
		}

		let clearContentTitle = NSLocalizedString("Clear Content", comment: "Clear Content button")
		let clearContentAction = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completion in
			guard let self else {
				completion(false)
				return
			}
			Task {
				await self.viewModel.clearContent(row)
				self.applySnapshot()
				completion(true)
			}
		}
		clearContentAction.image = UIImage(systemName: "trash")
		clearContentAction.accessibilityLabel = clearContentTitle
		clearContentAction.backgroundColor = UIColor.systemRed

		return UISwipeActionsConfiguration(actions: [clearContentAction])
	}

	private func formattedSize(_ bytes: Int) -> String {
		Int64(bytes).formatted(.byteCount(style: .file))
	}

}
