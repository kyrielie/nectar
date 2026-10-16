//
//  ArticleIconSchemeHandler.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 1/27/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import Foundation
import WebKit
import Articles

final class ArticleIconSchemeHandler: NSObject, WKURLSchemeHandler {
	weak var coordinator: SceneCoordinator?

	init(coordinator: SceneCoordinator) {
		self.coordinator = coordinator
	}

	func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {

		guard let url = urlSchemeTask.request.url, let coordinator = coordinator else {
			urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
			return
		}

		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return
		}
		let articleID = components.path
		guard let article = coordinator.articleFor(articleID) else {
			urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
			return
		}

		// Drawn directly (not through IconView, which is list-row chrome with a corner
		// radius and background logic) at 192 points so themes can size the avatar freely.
		// With no image the render is a transparent PNG, so a kept avatar never shows a
		// broken-image glyph.
		let side: CGFloat = 192
		let iconImage = IconImageCache.shared.imageForArticleAvatar(article)
		let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
		let renderedImage = renderer.image { _ in
			guard let image = iconImage?.image, image.size.width > 0, image.size.height > 0 else { return }
			let scale = min(side / image.size.width, side / image.size.height)
			let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
			image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
		}

		guard let data = renderedImage.pngData() else {
			urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
			return
		}

		let headerFields = ["Cache-Control": "no-cache"]
		if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headerFields) {
			urlSchemeTask.didReceive(response)
			urlSchemeTask.didReceive(data)
			urlSchemeTask.didFinish()
		}
	}

	func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
		urlSchemeTask.didFailWithError(URLError(.unknown))
	}
}
