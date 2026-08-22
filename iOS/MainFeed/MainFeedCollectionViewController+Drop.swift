//
//  MainFeedCollectionViewController+Drop.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 14/07/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit
import WebKit
import Account
import Articles
import RSCore
import RSTree
import RSWeb
import SafariServices
import UniformTypeIdentifiers

extension MainFeedCollectionViewController: UICollectionViewDropDelegate {

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
		guard let dragItem = coordinator.items.first?.dragItem,
			  let dragNode = dragItem.localObject as? Node,
			  let source = dragNode.parent?.representedObject as? Container,
			  let destIndexPath = coordinator.destinationIndexPath else {
				  return
			  }

		let isFolderDrop: Bool = {
			if dataSource.itemIdentifier(for: destIndexPath)?.node.representedObject is Folder, let propCell = collectionView.cellForItem(at: destIndexPath) {
				return coordinator.session.location(in: propCell).y >= 0
			}
			return false
		}()

		// Based on the drop we have to determine a node to start looking for a parent container.
		// For a non-folder drop onto row > 0, destNode is the predecessor of the drop
		// gap, not the gap itself -- isPredecessor records that distinction so the
		// targetIndex computation below can turn "predecessor's index" into "the slot
		// right after it" rather than reusing the predecessor's own index.
		var isPredecessor = false
		let destNode: Node? = {

			if isFolderDrop {
				return dataSource.itemIdentifier(for: destIndexPath)?.node
			} else {
				if destIndexPath.row == 0 {
					return dataSource.itemIdentifier(for: IndexPath(row: 0, section: destIndexPath.section))?.node
				} else if destIndexPath.row > 0 {
					isPredecessor = true
					return dataSource.itemIdentifier(for: IndexPath(row: destIndexPath.row - 1, section: destIndexPath.section))?.node
				} else {
					return nil
				}
			}

		}()

		// Now we start looking for the parent container
		let destinationContainer: Container? = {
			if let container = (destNode?.representedObject as? Container) ?? (destNode?.parent?.representedObject as? Container) {
				return container
			} else {
				// If we got here, we are trying to drop on an empty section header.  Go and find the Account for this section
				let sectionID = dataSource.snapshot().sectionIdentifiers[destIndexPath.section]
				return AccountManager.shared.existingAccount(accountID: sectionID)
			}
		}()

		guard let destination = destinationContainer else { return }

		if let feed = dragNode.representedObject as? Feed {
			// Position within the destination container's feed order, computed from
			// the Node tree's own sibling index rather than the flat collection-view
			// row (which isn't a reliable proxy once folder rows can be interleaved).
			// Only meaningful when dropping onto a specific feed row — an ordinary
			// reorder gesture. Left nil for the folder-drop case (isFolderDrop),
			// where position within the folder isn't implied by the gesture and the
			// existing append-to-end behavior is correct.
			let targetIndex: Int? = {
				guard !isFolderDrop, let destNode, destNode.representedObject is Feed,
					  let parent = destNode.parent, let destNodeIndex = parent.indexOfChild(destNode) else { return nil }
				// destNode is the item just before the previewed gap (isPredecessor),
				// so the gap itself is one slot after it -- except when row == 0,
				// where destNode IS the gap (nothing precedes it).
				let rawTargetIndex = isPredecessor ? destNodeIndex + 1 : destNodeIndex
				// Removing the dragged feed from earlier in this same container
				// shifts everything after it down by one before the insert runs,
				// so the raw index must be pulled back by one to still land in
				// the previewed gap.
				if parent.representedObject as? Container === source, let sourceIndex = parent.indexOfChild(dragNode), sourceIndex < rawTargetIndex {
					return rawTargetIndex - 1
				}
				return rawTargetIndex
			}()

			if source.account == destination.account {
				moveFeedInAccount(feed: feed, sourceContainer: source, destinationContainer: destination, targetIndex: targetIndex)
			} else {
				moveFeedBetweenAccounts(feed: feed, sourceContainer: source, destinationContainer: destination)
			}
			return
		}

		if let draggedFolder = dragNode.representedObject as? Folder {
			// Folder drags are same-account only — a folder being dropped
			// on a different account's section isn't a supported gesture
			// (there's no equivalent of moveFeedBetweenAccounts for folders,
			// since a Folder, unlike a Feed, isn't a value that makes sense
			// to duplicate/recreate on another account).
			guard source.account == destination.account else { return }

			// Guard against dropping a folder into itself or into one of
			// its own descendants, which would disconnect it from the
			// tree entirely.
			if let destinationFolder = destination as? Folder, draggedFolder.isAncestor(of: destinationFolder) {
				return
			}

			let targetIndex: Int? = {
				guard !isFolderDrop, let destNode, destNode.representedObject is Folder,
					  let parent = destNode.parent, let destNodeIndex = parent.indexOfChild(destNode) else { return nil }
				// See the equivalent comment in the Feed branch above: destNode is
				// the predecessor of the previewed gap, so the gap is one slot
				// after it, then pulled back by one if the dragged folder is being
				// removed from earlier in this same container.
				let rawTargetIndex = isPredecessor ? destNodeIndex + 1 : destNodeIndex
				if parent.representedObject as? Container === source, let sourceIndex = parent.indexOfChild(dragNode), sourceIndex < rawTargetIndex {
					return rawTargetIndex - 1
				}
				return rawTargetIndex
			}()

			moveFolderInAccount(folder: draggedFolder, sourceContainer: source, destinationContainer: destination, targetIndex: targetIndex)
		}
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {

		guard let destIndexPath = destinationIndexPath, destIndexPath.section > 0, collectionView.hasActiveDrag else {
			return UICollectionViewDropProposal(operation: .forbidden)
		}

		guard let destFeed = dataSource.itemIdentifier(for: destIndexPath)?.node.representedObject as? SidebarItem,
			  let destAccount = destFeed.account,
			  let destCell = collectionView.cellForItem(at: destIndexPath) else {
				  return UICollectionViewDropProposal(operation: .forbidden)
			  }

		// Validate account specific behaviors...
		if destAccount.behaviors.contains(.disallowFeedInMultipleFolders),
		   let sourceNode = session.localDragSession?.items.first?.localObject as? Node,
		   let sourceFeed = sourceNode.representedObject as? Feed,
		   sourceFeed.account?.accountID != destAccount.accountID && destAccount.hasFeed(withURL: sourceFeed.url) {
			return UICollectionViewDropProposal(operation: .forbidden)
		}

		// Determine the correct drop proposal
		if destFeed is Folder {
			if session.location(in: destCell).y >= 0 {
				return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
			} else {
				return UICollectionViewDropProposal(operation: .move, intent: .unspecified)
			}
		} else {
			return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
		}
	}

	func collectionView(_ collectionView: UICollectionView, canHandle session: any UIDropSession) -> Bool {
		return session.localDragSession != nil
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
	}

	func moveFeedInAccount(feed: Feed, sourceContainer: Container, destinationContainer: Container, targetIndex: Int?) {
		// No early return on sourceContainer === destinationContainer — a
		// same-container drop with a targetIndex is exactly the reorder
		// gesture this feature exists for.
		BatchUpdate.shared.start()
		sourceContainer.account?.moveFeed(feed, from: sourceContainer, to: destinationContainer, targetIndex: targetIndex) { result in
			BatchUpdate.shared.end()
			switch result {
			case .success:
				break
			case .failure(let error):
				self.presentError(error)
			}
		}
	}

	func moveFolderInAccount(folder: Folder, sourceContainer: Container, destinationContainer: Container, targetIndex: Int?) {
		// No early return on sourceContainer === destinationContainer — a
		// same-container drop with a targetIndex is the folder-reordering
		// gesture; depth-cap and cycle checks happen in the delegate
		// (moveFolder) and just above this call (isAncestor(of:)).
		BatchUpdate.shared.start()
		sourceContainer.account?.moveFolder(folder, from: sourceContainer, to: destinationContainer, targetIndex: targetIndex) { result in
			BatchUpdate.shared.end()
			switch result {
			case .success:
				break
			case .failure(let error):
				self.presentError(error)
			}
		}
	}

	func moveFeedBetweenAccounts(feed: Feed, sourceContainer: Container, destinationContainer: Container) {

		if let existingFeed = destinationContainer.account?.existingFeed(withURL: feed.url) {

			BatchUpdate.shared.start()
			destinationContainer.account?.addFeed(existingFeed, to: destinationContainer) { result in
				switch result {
				case .success:
					sourceContainer.account?.removeFeed(feed, from: sourceContainer) { result in
						BatchUpdate.shared.end()
						switch result {
						case .success:
							break
						case .failure(let error):
							self.presentError(error)
						}
					}
				case .failure(let error):
					BatchUpdate.shared.end()
					self.presentError(error)
				}
			}

		} else {

			BatchUpdate.shared.start()
			destinationContainer.account?.createFeed(url: feed.url, name: feed.editedName, container: destinationContainer, validateFeed: false) { result in
				switch result {
				case .success:
					sourceContainer.account?.removeFeed(feed, from: sourceContainer) { result in
						BatchUpdate.shared.end()
						switch result {
						case .success:
							break
						case .failure(let error):
							self.presentError(error)
						}
					}
				case .failure(let error):
					BatchUpdate.shared.end()
					self.presentError(error)
				}
			}

		}
	}

}
