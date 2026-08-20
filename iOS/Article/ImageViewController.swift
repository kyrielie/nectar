//
//  ImageViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 10/12/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit

final class ImageViewController: UIViewController {
	@IBOutlet var imageScrollView: ImageScrollView!
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var titleBackground: UIVisualEffectView!
	@IBOutlet var titleLeading: NSLayoutConstraint!
	@IBOutlet var titleTrailing: NSLayoutConstraint!

	private var shareButtonItem: UIBarButtonItem?

	var image: UIImage!
	var imageTitle: String?
	var zoomedFrame: CGRect {
		return imageScrollView.zoomedFrame
	}

	// Fallback state (nectar-toolbar-image-link-viewer.md, decision 4):
	// set via showFallbackState(caption:) instead of the image/imageTitle
	// properties above, when imageWasClicked exhausts every source for a
	// tapped image/image-link (cache miss, then live fetch/decode failure).
	// Distinct from the loading state -- this view controller is only
	// presented once resolution has already finished, one way or the other.
	private var isShowingFallback = false
	private var fallbackCaption: String?

	/// Call instead of setting `image`/`imageTitle` directly when showing
	/// the bundled "sorry!" illustration rather than a real image. Must be
	/// called before the view loads (same timing contract `image`/
	/// `imageTitle` already have via SceneCoordinator.showFullScreenImage).
	func showFallbackState(caption: String?) {
		isShowingFallback = true
		fallbackCaption = caption
	}

	override var keyCommands: [UIKeyCommand]? {
		return [
			UIKeyCommand(
				title: NSLocalizedString("Close Image", comment: "Close Image"),
				action: #selector(done(_:)),
				input: " "
			)
		]
	}

	override func viewDidLoad() {
        super.viewDidLoad()

		let closeButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(done(_:)))
		closeButtonItem.tintColor = Assets.Colors.primaryAccent
		navigationItem.leftBarButtonItem = closeButtonItem

		if isShowingFallback {
			setUpFallbackState()
			return
		}

		let shareButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(share(_:)))
		shareButtonItem.tintColor = Assets.Colors.primaryAccent
		navigationItem.rightBarButtonItem = shareButtonItem
		self.shareButtonItem = shareButtonItem

        imageScrollView.setup()
        // The image viewer is full-screen, so the scroll view ignores
        // the navigation bar and safe area insets. Otherwise the image is pushed down
        // and doesn’t match the zoom transition’s target frame.
        imageScrollView.contentInsetAdjustmentBehavior = .never
        imageScrollView.imageScrollViewDelegate = self
        imageScrollView.imageContentMode = .aspectFit
        imageScrollView.initialOffset = .center
		imageScrollView.display(image: image)

		titleLabel.text = imageTitle ?? ""
		layoutTitleLabel()

		guard imageTitle != "" else {
			titleBackground.removeFromSuperview()
			return
		}
		titleBackground.layer.cornerRadius = 6
    }

	/// No share action (nothing to share -- the bundled asset, not the
	/// person's own content) and no zoom/pan (a fixed illustration, not a
	/// photo to inspect). Reuses imageScrollView purely as a
	/// non-interactive image host: display the bundled asset via the same
	/// aspect-fit display(image:) path, then disable zoom so it reads as a
	/// static state rather than an image the person might try to pinch.
	private func setUpFallbackState() {
		imageScrollView.setup()
		imageScrollView.contentInsetAdjustmentBehavior = .never
		imageScrollView.imageScrollViewDelegate = self
		imageScrollView.imageContentMode = .aspectFit
		imageScrollView.initialOffset = .center
		imageScrollView.isUserInteractionEnabled = false
		imageScrollView.display(image: Assets.Images.imageFallbackIllustration)

		let caption = (fallbackCaption?.isEmpty == false ? fallbackCaption : nil) ?? NSLocalizedString("Image unavailable", comment: "Fallback caption when an image/image-link can't be resolved")
		titleLabel.text = caption
		layoutTitleLabel()
		titleBackground.layer.cornerRadius = 6
	}

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		coordinator.animate(alongsideTransition: { [weak self] _ in
			self?.imageScrollView.resize()
		})
	}

	@IBAction func share(_ sender: Any) {
		guard let image else {
			return
		}
		let activityViewController = UIActivityViewController(activityItems: [image], applicationActivities: nil)
		activityViewController.popoverPresentationController?.barButtonItem = shareButtonItem
		present(activityViewController, animated: true)
	}

	@IBAction func done(_ sender: Any) {
		dismiss(animated: true)
	}

	private func layoutTitleLabel() {
		let width = view.frame.width
		let multiplier = traitCollection.userInterfaceIdiom == .pad ? CGFloat(0.1) : CGFloat(0.04)
		titleLeading.constant += width * multiplier
		titleTrailing.constant -= width * multiplier
		titleLabel.layoutIfNeeded()
	}
}

// MARK: ImageScrollViewDelegate

extension ImageViewController: ImageScrollViewDelegate {

	func imageScrollViewDidGestureSwipeUp(imageScrollView: ImageScrollView) {
		dismiss(animated: true)
	}

	func imageScrollViewDidGestureSwipeDown(imageScrollView: ImageScrollView) {
		dismiss(animated: true)
	}
}
