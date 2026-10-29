//
//  WebViewController+Progress.swift
//  NetNewsWire-iOS
//
//  Reading progress, scroll tracking, and scroll restoration for WebViewController.
//

import UIKit
import WebKit
import Articles
import os

extension WebViewController: UIScrollViewDelegate {

	public func scrollViewDidScroll(_ scrollView: UIScrollView) {
		scrollPositionQueue.add(self, #selector(scrollPositionDidChange))
	}

	@objc func scrollPositionDidChange() {
		webView?.evaluateJavaScript("({ scrollY: window.scrollY, scrollHeight: document.body.scrollHeight, innerHeight: window.innerHeight })") { result, error in
			guard error == nil, let result = result as? [String: Any] else {
				Self.logger.debug("scrollPositionDidChange: evaluateJavaScript failed, error=\(String(describing: error), privacy: .public)")
				return
			}
			let javascriptScrollY = result["scrollY"] as? Int ?? 0
			// I don't know why this value gets returned sometimes, but it is in error
			guard javascriptScrollY != 33554432 else {
				Self.logger.debug("scrollPositionDidChange: discarding known-bad sentinel scrollY value")
				return
			}
			guard !self.isRestoringScrollPosition else {
				Self.logger.debug("scrollPositionDidChange: discarding sample during restore settling (scrollY=\(javascriptScrollY, privacy: .public)) -- not yet confirmed via scrollRestoreComplete")
				return
			}
			if let scrollHeight = result["scrollHeight"] as? Double, scrollHeight > 0 {
				if scrollHeight < self.maxObservedScrollHeight - 1 {
					Self.logger.debug("scrollPositionDidChange: discarding sample, scrollHeight shrank (observed=\(scrollHeight, privacy: .public) max=\(self.maxObservedScrollHeight, privacy: .public)) -- unsettled reflow")
					return
				}
				self.maxObservedScrollHeight = max(self.maxObservedScrollHeight, scrollHeight)
			}
			// Stub or still-settling provisional content: don't write position, credit
			// Reading Stats, mark read, or persist.
			guard !self.isContentProvisional else {
				Self.logger.debug("scrollPositionDidChange: discarding sample, content is provisional (scrollY=\(javascriptScrollY, privacy: .public))")
				return
			}
			self.windowScrollY = javascriptScrollY

			// Mark read once the viewport bottom reaches ReadingProgressEvaluator.completionThreshold
			// (shared with ReadingStatsTracker). The math lives there so it is testable without a WKWebView.
			if let scrollHeight = result["scrollHeight"] as? Double,
			   let innerHeight = result["innerHeight"] as? Double,
			   let sample = ReadingProgressEvaluator.sample(scrollY: Double(javascriptScrollY), scrollHeight: scrollHeight, viewportHeight: innerHeight) {
				ReadingStatsTracker.shared.recordProgress(sample.rawFraction)
				if sample.isComplete {
					self.coordinator.markCurrentArticleAsReadFromScrollCompletion()
				}

				// Page counter; reuses this JS payload rather than a second round trip.
				switch AppDefaults.shared.pageCounterDisplayMode {
				case .off:
					break
				case .percentage:
					self.pageCounterLabel.text = "\(sample.percentRounded)%"
				case .pageCount:
					// nil when the viewport reports zero height; leave the label as-is
					// rather than converting an infinite ratio to Int.
					if let page = ReadingProgressEvaluator.pageCounter(for: sample) {
						self.pageCounterLabel.text = "\(page.current)/\(page.total)"
					}
				}

				// Visible reading progress; reuses the same payload (sample.fraction is the 0...1 value).
				if let article = self.article, let account = article.account {
					let articleID = article.articleID
					let readingProgress = sample.fraction
					self.lastKnownReadingProgress = readingProgress
					Task {
						await account.saveReadingProgress(readingProgress, forArticleID: articleID)
					}
				}
			}
		}
	}

	/// Synchronously persists the last known scroll position/progress (no JS evaluation,
	/// so nothing races view teardown). See viewWillDisappear.
	func flushLastKnownScrollState() {
		guard let article, let account = article.account else { return }
		let articleID = article.articleID
		let scrollY = windowScrollY
		let readingProgress = lastKnownReadingProgress
		Task {
			await account.saveScrollPosition(Double(scrollY), forArticleID: articleID)
			if let readingProgress {
				await account.saveReadingProgress(readingProgress, forArticleID: articleID)
			}
		}
	}

	/// Scrolls to the element a same-document fragment link points at. The origin is captured
	/// before the jump and pushed onto scrollJumpHistory only when the target exists, so Scroll
	/// Back works. When the id is not in the page, the link behaves as it did before this path
	/// existed (opens externally, unless disableArticleLinks is on) instead of going dead:
	/// decisionHandler has to be answered synchronously, so the existence check happens here.
	func handleSameDocumentAnchor(_ url: URL) {
		guard let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
			  let json = try? JSONEncoder().encode(["id": id]) else {
			return
		}
		let encoded = json.base64EncodedString()
		let originY = Double(windowScrollY)
		webView?.evaluateJavaScript("scrollToAnchor(\"\(encoded)\")") { [weak self] result, _ in
			guard let self else {
				return
			}
			if (result as? Bool) == true {
				self.scrollJumpHistory.append(originY)
			} else if !AppDefaults.shared.disableArticleLinks {
				self.openExternalLink(url)
			}
		}
	}

	func scrollToHeading(tocIndex: Int) {
		scrollJumpHistory.append(Double(windowScrollY))
		guard let json = try? JSONEncoder().encode(["tocIndex": tocIndex]) else { return }
		let encoded = json.base64EncodedString()
		webView?.evaluateJavaScript("scrollToHeading(\"\(encoded)\")")
	}

	/// Pops the most recent pre-jump position (pushed by scrollToHeading/scrollToAnnotation)
	/// and scrolls back to it; no-op if none. Callers wiring this to a toolbar item should
	/// hide or disable it based on scrollJumpHistory.isEmpty.
	func scrollBack() {
		guard let previousY = scrollJumpHistory.popLast() else { return }
		let payload = ["y": previousY]
		guard let json = try? JSONEncoder().encode(payload) else { return }
		let encoded = json.base64EncodedString()
		webView?.evaluateJavaScript("scrollToWindowY(\"\(encoded)\")")
	}

	var isScrollBackAvailable: Bool {
		!scrollJumpHistory.isEmpty
	}

	func scrollToTop() {
		webView?.evaluateJavaScript("window.scrollTo({ top: 0, behavior: 'instant' });")
	}

	func scrollToBottom() {
		webView?.evaluateJavaScript("window.scrollTo({ top: document.body.scrollHeight, behavior: 'instant' });")
	}
}
