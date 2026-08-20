//
//  ToolbarsCustomizerViewController+Drag.swift
//  NetNewsWire-iOS
//
//  Starts a local-reorder drag for ToolbarFunctionCell's .reorder()
//  handle in the Functions section. Local-only (no NSItemProvider
//  payload meant to leave the app), unlike
//  MainFeedCollectionViewController+Drag.swift's cross-container feed
//  drags -- the item's identity for the drop side comes from
//  UIDragItem.localObject plus UICollectionViewDropCoordinator's own
//  sourceIndexPath, not from decoding provider data.
//

import UIKit

extension ToolbarsCustomizerViewController: UICollectionViewDragDelegate {
	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		guard indexPath.section == functionsSection else { return [] }
		let function = functionOrder[indexPath.item]
		// The item provider's content is never read on the drop side --
		// this drag never leaves the collection view -- but an
		// NSItemProvider is required to construct a UIDragItem, so it
		// carries the function's rawValue as a placeholder payload.
		let itemProvider = NSItemProvider(object: function.rawValue as NSString)
		let dragItem = UIDragItem(itemProvider: itemProvider)
		dragItem.localObject = function
		return [dragItem]
	}
}
