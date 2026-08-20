//
//  ToolbarsCustomizerViewController+Drop.swift
//  NetNewsWire-iOS
//
//  Commits the Functions-section reorder a +Drag.swift session starts.
//  Local move only: proposals outside the Functions section, or from a
//  session that didn't originate in this collection view, are forbidden
//  rather than accepted, since there's nothing meaningful to insert here
//  from an external drag (unlike MainFeedCollectionViewController+Drop.swift,
//  which does accept external feed URLs).
//

import UIKit

extension ToolbarsCustomizerViewController: UICollectionViewDropDelegate {

	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
		guard session.localDragSession != nil,
			  let destinationIndexPath,
			  destinationIndexPath.section == functionsSection else {
			return UICollectionViewDropProposal(operation: .forbidden)
		}
		return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
	}

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
		guard let item = coordinator.items.first,
			  let sourceIndexPath = item.sourceIndexPath,
			  let destinationIndexPath = coordinator.destinationIndexPath,
			  sourceIndexPath.section == functionsSection,
			  destinationIndexPath.section == functionsSection else {
			return
		}

		// Write the new order first: the preview refresh below and any
		// later, unrelated reload both need AppDefaults to already hold
		// the new order at the time they run.
		var order = functionOrder
		let function = order.remove(at: sourceIndexPath.item)
		order.insert(function, at: destinationIndexPath.item)
		AppDefaults.shared.setToolbarFunctionOrder(order, for: activeBar)

		collectionView.performBatchUpdates {
			collectionView.deleteItems(at: [sourceIndexPath])
			collectionView.insertItems(at: [destinationIndexPath])
		}
		coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)

		// setToolbarFunctionOrder(_:for:) above posts
		// UserDefaults.didChangeNotification while the drop is still
		// animating (hasActiveDrop is still true), which
		// userDefaultsDidChange() deliberately ignores to avoid stomping
		// this same drop's animation -- so that notification's reload
		// never reaches the Preview section, and nothing else touches it
		// (the performBatchUpdates above only reindexes the two Functions
		// rows). Refresh the already-visible preview cell directly rather
		// than count on a reload that's guaranteed to be skipped.
		let previewIndexPath = IndexPath(item: 0, section: previewSection)
		if let previewCell = collectionView.cellForItem(at: previewIndexPath) as? ToolbarPreviewCell {
			previewCell.configure(bar: activeBar)
		}
	}
}
