//
//  TableOfContentsViewController.swift
//  NetNewsWire-iOS
//

import UIKit

/// Full-screen table of contents for the current article. Entries come from
/// WebViewController.fetchTableOfContents(completionHandler:) (see that file
/// and main_ios.js's tocNodes()/getTableOfContents for how entries are
/// addressed -- by tocIndex, a position in document order, not by id, since
/// anthology/merged-book content reuses the same id across separate books).
///
/// A single, non-merged book has at most one h1-tagged entry (the book's own
/// title) and renders as a flat, non-expandable chapter list. A merged/
/// anthology book has more than one h1-tagged entry -- each begins a group of
/// that book's own h2 chapter entries (ordinary chapters and Calibre's
/// "Afterword" closer alike), up to the next h1 -- and renders as an
/// expand/collapse outline, one group per book.
final class TableOfContentsViewController: UICollectionViewController {

	private enum Item: Hashable {
		case book(TableOfContentsEntry)
		case chapter(TableOfContentsEntry)

		var entry: TableOfContentsEntry {
			switch self {
			case .book(let entry), .chapter(let entry):
				return entry
			}
		}
	}

	private let entries: [TableOfContentsEntry]
	private let onSelectChapter: (Int) -> Void
	private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!

	init(entries: [TableOfContentsEntry], onSelectChapter: @escaping (Int) -> Void) {
		self.entries = entries
		self.onSelectChapter = onSelectChapter

		var config = UICollectionLayoutListConfiguration(appearance: .plain)
		config.showsSeparators = true
		let layout = UICollectionViewCompositionalLayout.list(using: config)
		super.init(collectionViewLayout: layout)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// A single book's own title is more useful here than a generic
		// label -- for an anthology (several books' worth of entries),
		// there's no single title to show, so the generic label remains.
		if !isAnthology, let bookTitle = bookEntries.first?.text, !bookTitle.isEmpty {
			title = bookTitle
		} else {
			title = NSLocalizedString("Table of Contents", comment: "Table of Contents")
		}
		navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismissTableOfContents))

		configureDataSource()
		applySnapshot()
	}

	@objc private func dismissTableOfContents() {
		dismiss(animated: true)
	}

	// MARK: Grouping

	/// h1 entries are book boundaries; every following entry up to the next
	/// h1 belongs to that book. Book/chapter separation is by tagName (h1
	/// vs. h2), not by CSS class -- Calibre's toc-heading class marks only
	/// a subset of chapter h2s (Afterword / repeated one-shot titles), so
	/// it is never a reliable discriminant on its own.
	private var bookEntries: [TableOfContentsEntry] {
		entries.filter { $0.tagName == "h1" }
	}

	private var isAnthology: Bool {
		bookEntries.count > 1
	}

	/// [book entry -> that book's chapter entries], in document order. Only
	/// meaningful when isAnthology is true.
	private var chaptersByBook: [(book: TableOfContentsEntry, chapters: [TableOfContentsEntry])] {
		var result: [(book: TableOfContentsEntry, chapters: [TableOfContentsEntry])] = []
		var currentChapters: [TableOfContentsEntry] = []

		for entry in entries {
			if entry.tagName == "h1" {
				if let last = result.popLast() {
					result.append((last.book, currentChapters))
				}
				result.append((entry, []))
				currentChapters = []
			} else {
				// tocNodes() only ever emits h1 or h2 (see main_ios.js), so
				// anything reaching here is an h2 -- an ordinary chapter,
				// Calibre's "Afterword" closer, or a one-shot's repeated
				// title heading. All are real, navigable chapter entries.
				currentChapters.append(entry)
			}
		}
		if let last = result.popLast() {
			result.append((last.book, currentChapters))
		}
		return result
	}

	/// Books with no chapter entries of their own (e.g. a true one-chapter work with no
	/// repeated-title/Afterword-style .toc-heading markup at all between its <h1> and the
	/// next book's). Rendering an .outlineDisclosure() accessory on one of these produces
	/// a chevron that expands to nothing -- confusing, and easy to mistake for "there's no
	/// way to get to this book." These render as plain, directly-tappable rows instead,
	/// same as the non-anthology flat-list case.
	private var tocIndicesWithNoChapters: Set<Int> {
		Set(chaptersByBook.filter { $0.chapters.isEmpty }.map { $0.book.tocIndex })
	}

	// MARK: Data source

	private func configureDataSource() {
		let chapterCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, indexPath, item in
			var content = cell.defaultContentConfiguration()
			content.text = item.entry.text
			cell.contentConfiguration = content
			cell.accessories = []
		}

		let emptyBookIndices = tocIndicesWithNoChapters
		let bookCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, indexPath, item in
			var content = cell.defaultContentConfiguration()
			content.text = item.entry.text
			content.textProperties.font = .preferredFont(forTextStyle: .headline)
			cell.contentConfiguration = content
			cell.accessories = emptyBookIndices.contains(item.entry.tocIndex) ? [] : [.outlineDisclosure()]
		}

		dataSource = UICollectionViewDiffableDataSource<Int, Item>(collectionView: collectionView) { collectionView, indexPath, item in
			switch item {
			case .book:
				return collectionView.dequeueConfiguredReusableCell(using: bookCellRegistration, for: indexPath, item: item)
			case .chapter:
				return collectionView.dequeueConfiguredReusableCell(using: chapterCellRegistration, for: indexPath, item: item)
			}
		}
	}

	private func applySnapshot() {
		if !isAnthology {
			// Flat, non-expandable list -- there's nothing to disclose.
			var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<Item>()
			var chapterItems = entries.filter { $0.tagName != "h1" }.map { Item.chapter($0) }

			// A true single-chapter work (Calibre or AO3-fetched alike) has
			// no h2 chapter entries at all -- only its own h1 book title,
			// which the filter above always excludes. Rather than leave the
			// screen empty (the reported bug: AO3-fetched single-chapter
			// works showed a blank Table of Contents), fall back to the
			// book entry itself as the one navigable row -- tapping it
			// scrolls to the top of the article, same as tapping a chapter
			// row does for any other entry.
			if chapterItems.isEmpty, let bookEntry = bookEntries.first {
				chapterItems = [.chapter(bookEntry)]
			}

			sectionSnapshot.append(chapterItems)
			dataSource.apply(sectionSnapshot, to: 0, animatingDifferences: false)
			return
		}

		var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<Item>()
		let groups = chaptersByBook
		let bookItems = groups.map { Item.book($0.book) }
		sectionSnapshot.append(bookItems)

		for group in groups {
			let bookItem = Item.book(group.book)
			let chapterItems = group.chapters.map { Item.chapter($0) }
			sectionSnapshot.append(chapterItems, to: bookItem)
		}

		// Land on the TOC already showing where you are; collapsed elsewhere.
		if let firstBookItem = bookItems.first {
			sectionSnapshot.expand([firstBookItem])
		}

		dataSource.apply(sectionSnapshot, to: 0, animatingDifferences: false)
	}

	// MARK: UICollectionViewDelegate

	override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		collectionView.deselectItem(at: indexPath, animated: true)
		guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

		switch item {
		case .chapter(let entry):
			onSelectChapter(entry.tocIndex)
			dismiss(animated: true)
		case .book(let entry):
			// Tapping the row body jumps to the book's own heading, same as a
			// chapter row. This is separate from the outlineDisclosure
			// accessory's own chevron tap target, which still expands/
			// collapses independently of cell selection -- so browsing an
			// anthology's chapter list via the chevron still works.
			onSelectChapter(entry.tocIndex)
			dismiss(animated: true)
		}
	}

}
