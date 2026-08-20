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

		// Write the new order first so the section's post-drop
		// reloadData() (triggered by this same write's
		// UserDefaults.didChangeNotification, see
		// ToolbarsCustomizerViewController.userDefaultsDidChange())
		// reflects it -- the performBatchUpdates call below only needs to
		// animate the visual move, not carry the source of truth.
		var order = functionOrder
		let function = order.remove(at: sourceIndexPath.item)
		order.insert(function, at: destinationIndexPath.item)
		AppDefaults.shared.setToolbarFunctionOrder(order, for: activeBar)

		collectionView.performBatchUpdates {
			collectionView.deleteItems(at: [sourceIndexPath])
			collectionView.insertItems(at: [destinationIndexPath])
		}
		coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
	}
}
