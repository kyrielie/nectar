//
//  WebViewController+Annotations.swift
//  NetNewsWire-iOS
//
//  Annotations (highlights + notes), inline text edits, and selection popovers.
//

import UIKit
import SwiftUI
import WebKit
import Articles
import Account

// MARK: - Annotation Bridge Types

/// Shapes returned by annotations.js (renderAnnotationsEncoded/addHighlightFromSelection)
/// over the base64-JSON bridge: `AnnotationSelector` is a live selection resolved to a
/// selector; `ReanchorReport` is a render's {moved, orphanedIDs} report.
struct AnnotationSelector: Codable {
	let annotationID: String
	let color: String
	let quoteExact: String
	let quotePrefix: String
	let quoteSuffix: String
	let rootSelector: String
	let startOffset: Int
	let endOffset: Int
	/// See Annotation.chapterTitle; computed by annotations.js's nearestChapterTitle.
	let chapterTitle: String?
}

struct ReanchorReport: Codable {
	struct Moved: Codable {
		let annotationID: String
		let startOffset: Int
		let endOffset: Int
		let quoteExact: String
		let quotePrefix: String
		let quoteSuffix: String
		let chapterTitle: String?
	}
	let moved: [Moved]
	let orphanedIDs: [String]
}

/// Shape returned by annotations.js's computeTextEditPlanEncoded: an overlap
/// conflict, or the other rows an edit's length delta shifts, with
/// quote/prefix/suffix/chapterTitle already recomputed against the simulated
/// post-edit text. See docs/annotations.md, "Applying edits".
struct TextEditPlan: Codable {
	struct Shifted: Codable {
		let annotationID: String
		let startOffset: Int
		let endOffset: Int
		let quoteExact: String
		let quotePrefix: String
		let quoteSuffix: String
		let chapterTitle: String?
	}
	let status: String
	let delta: Int?
	let shifted: [Shifted]
	let conflictingAnnotationID: String?

	private enum CodingKeys: String, CodingKey {
		case status, delta, shifted, conflictingAnnotationID
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		status = try container.decode(String.self, forKey: .status)
		delta = try container.decodeIfPresent(Int.self, forKey: .delta)
		shifted = try container.decodeIfPresent([Shifted].self, forKey: .shifted) ?? []
		conflictingAnnotationID = try container.decodeIfPresent(String.self, forKey: .conflictingAnnotationID)
	}
}

// MARK: - Annotations (highlights + notes)

extension WebViewController {

	/// Wires annotations.js's `selectionchange`/tap listeners for the loaded document,
	/// so selections post `textWasSelected` and taps on a `<mark>` post
	/// `annotationWasTapped`. Runs on every navigation, not only when annotations
	/// exist, since a chapter with none still needs to support creating its first.
	///
	/// Reads annotationCreationMethod fresh each call (not cached), like the other
	/// per-dequeue settings, so a change applies on the next article load but not
	/// retroactively to what's on screen.
	func initAnnotations() {
		let mode = AppDefaults.shared.annotationCreationMethod
		guard let argsJSON = try? JSONSerialization.data(withJSONObject: ["mode": mode.rawValue]) else { return }
		let encodedArgs = argsJSON.base64EncodedString()

		webView?.evaluateJavaScript("Annotations.initAnnotations(\"\(encodedArgs)\")") { _, error in
			if let error {
				Self.logger.error("initAnnotations: Annotations.initAnnotations() JS call failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	/// Sets the ten --nnw-highlight-* CSS custom properties (light + dark per
	/// Annotation.Color) on the document root from AppDefaults.shared.highlightPalette,
	/// so core.css's mark.nnw-highlight rules resolve against the selected palette
	/// instead of their hardcoded fallback hex. See docs/annotations.md, "Color palette".
	///
	/// Both light and dark values are always set; core.css's own
	/// `@media (prefers-color-scheme: dark)` block switches between them live, so no
	/// registerForTraitChanges hook is needed. Called from webView(_:didFinish:) on
	/// every render and from highlightPaletteDidChange(_:), where existing <mark>s
	/// repaint for free because they read the custom property.
	func applyHighlightPaletteColors() {
		let palette = AppDefaults.shared.highlightPalette
		let light = palette.lightHexSet
		let dark = palette.darkHexSet

		var declarations = ""
		for color in Annotation.Color.allCases {
			declarations += "document.documentElement.style.setProperty('--nnw-highlight-\(color.rawValue)', '\(light[color])');"
			declarations += "document.documentElement.style.setProperty('--nnw-highlight-\(color.rawValue)-dark', '\(dark[color])');"
		}

		webView?.evaluateJavaScript(declarations) { _, error in
			if let error {
				Self.logger.error("applyHighlightPaletteColors: JS injection failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	@objc func highlightPaletteDidChange(_ note: Notification) {
		applyHighlightPaletteColors()
	}

	/// First-run rule-driven text replacement (categories 1 and 3; see
	/// docs/annotations.md, "Storage shape"). Applies the typo table, reader-insert
	/// table and custom rules to the article's canonical text, writing one edit row
	/// (`hasHighlight = false`) per match through the same pipeline saveTextEdit uses.
	///
	/// "First time" is detected by absence: if any edit row with `hasHighlight == false`
	/// and a non-nil `originalText` exists, this already ran (or a person reverted a row
	/// that is still reviewable in Edit History). Re-running would duplicate matches or
	/// resurrect a reverted one, so it only runs when that set is empty. Called before
	/// loadAndRenderAnnotations() on every load so new matches render the same load.
	@MainActor
	func applyTextReplacementRulesIfNeeded() async {
		guard AppDefaults.shared.textReplacementApplyAutomatically else { return }
		guard let article, let account = article.account else { return }
		let articleID = article.articleID

		let existing = await account.fetchAnnotations(forArticleID: articleID)
		let alreadyRan = existing.contains { !$0.hasHighlight && $0.originalText != nil }
		guard !alreadyRan else { return }

		var table = TextReplacementRuleTable()
		if AppDefaults.shared.textReplacementTypoFixesEnabled {
			table.rules.append(contentsOf: AppDefaults.shared.textReplacementTypoTable.rules)
		}
		// A per-work override takes precedence over the global reader-insert table:
		// prepending its rules suffices because TextReplacementRuleEngine lets the earlier
		// rule win an overlap (see TextReplacementPerWorkOverride.mergedReaderInsertTable).
		// A nil bookKey falls through to the global table.
		let mergedReaderInsertTable = AppDefaults.shared.textReplacementPerWorkOverride.mergedReaderInsertTable(
			forBookKey: article.bookKey,
			global: AppDefaults.shared.textReplacementReaderInsertTable
		)
		table.rules.append(contentsOf: mergedReaderInsertTable.rules)
		table.rules.append(contentsOf: AppDefaults.shared.textReplacementCustomTable.rules)
		let quoteConversionEnabled = AppDefaults.shared.textReplacementQuoteConversionEnabled
		guard !table.rules.isEmpty || quoteConversionEnabled else { return }

		guard let textResult = try? await self.webView?.evaluateJavaScript("Annotations.getArticleText(\".articleBody\")"),
			  let text = textResult as? String, !text.isEmpty else {
			return
		}

		// Rule-table matches (categories 1/3) and quote conversion (category 2) are found
		// independently. On an overlapping span the rule-table match wins and the quote
		// candidate is dropped: a rule is an explicit correction, quote conversion a
		// blanket style pass.
		var matches = TextReplacementRuleEngine.findMatches(applying: table, to: text)
		if quoteConversionEnabled {
			let ruleRanges = matches.map { NSRange(location: $0.startOffset, length: $0.endOffset - $0.startOffset) }
			let quoteMatches = TextReplacementQuoteConversion.findMatches(in: text).filter { quoteMatch in
				let quoteRange = NSRange(location: quoteMatch.startOffset, length: quoteMatch.endOffset - quoteMatch.startOffset)
				return !ruleRanges.contains { NSIntersectionRange($0, quoteRange).length > 0 }
			}
			matches.append(contentsOf: quoteMatches)
		}
		guard !matches.isEmpty else { return }

		// Capture prefix/suffix as selectorForRange does in JS (CONTEXT_CHARS = 200). Empty
		// values would starve resolveAnnotation's disambiguation (scoreCandidate) if this
		// quote later needs multi-match resolution.
		let nsText = text as NSString
		let contextChars = 200

		// Apply in descending offset order (as for manual edits) so an earlier match's
		// offset is never invalidated by a later match's length delta.
		let descending = matches.sorted { $0.startOffset > $1.startOffset }
		var appliedCount = 0
		for match in descending {
			let prefixStart = max(0, match.startOffset - contextChars)
			let quotePrefix = nsText.substring(with: NSRange(location: prefixStart, length: match.startOffset - prefixStart))
			let suffixEnd = min(nsText.length, match.endOffset + contextChars)
			let quoteSuffix = nsText.substring(with: NSRange(location: match.endOffset, length: suffixEnd - match.endOffset))

			let annotationID = UUID().uuidString
			let now = Date()
			let annotation = Annotation(
				annotationID: annotationID,
				articleID: articleID,
				bookKey: nil,
				quoteExact: match.originalText,
				quotePrefix: quotePrefix,
				quoteSuffix: quoteSuffix,
				startOffset: match.startOffset,
				endOffset: match.endOffset,
				color: .yellow,
				note: nil,
				hasHighlight: false,
				originalText: match.originalText,
				replacementText: match.replacementText,
				createdAt: now,
				updatedAt: now
			)
			await account.saveAnnotation(annotation)
			appliedCount += 1
		}

		if appliedCount > 0 {
			Self.logger.debug("applyTextReplacementRulesIfNeeded: applied \(appliedCount, privacy: .public) rule-driven replacements for articleID=\(articleID, privacy: .public)")
			// Surface a one-time summary banner via ArticleViewController. The debug log above
			// is kept for diagnosing reports of unexpected replacements. A nil closure just
			// means no visible banner; the pass has already completed and persisted.
			onTextReplacementReplacementsApplied?(appliedCount)
		}
	}

	/// Fetches saved annotations and hands them to annotations.js's
	/// renderAnnotationsEncoded, which resolves each against the fresh DOM and draws it.
	/// "Moved" annotations get their stored anchor updated so the next render hits the
	/// stored-offset fast path; "orphaned" ones are marked (Annotation.orphanedAt),
	/// never deleted, so a note is not silently lost.
	func loadAndRenderAnnotations() {
		guard let article, let account = article.account else { return }
		let articleID = article.articleID

		Task {
			let annotations = await account.fetchAnnotations(forArticleID: articleID)
			guard !annotations.isEmpty else { return }

			// Discard if the person navigated to a different article during the fetch.
			guard self.article?.articleID == articleID else {
				Self.logger.debug("loadAndRenderAnnotations: articleID changed before annotation fetch resolved, discarding for articleID=\(articleID, privacy: .public)")
				return
			}

			guard let json = try? JSONEncoder().encode(annotations) else { return }
			let encoded = json.base64EncodedString()

			do {
				let result = try await self.webView?.evaluateJavaScript("Annotations.renderAnnotationsEncoded(\"\(encoded)\")")
				guard let b64 = result as? String, let data = Data(base64Encoded: b64) else {
					Self.logger.error("loadAndRenderAnnotations: renderAnnotationsEncoded() returned an unexpected result type or invalid base64")
					return
				}
				guard let report = try? JSONDecoder().decode(ReanchorReport.self, from: data) else {
					Self.logger.error("loadAndRenderAnnotations: failed to decode ReanchorReport from renderAnnotationsEncoded() result")
					return
				}
				self.reconcile(report, account: account)
			} catch {
				Self.logger.error("loadAndRenderAnnotations: renderAnnotationsEncoded() JS call failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	private func reconcile(_ report: ReanchorReport, account: Account) {
		Task {
			for moved in report.moved {
				await account.reanchorAnnotation(
					annotationID: moved.annotationID,
					startOffset: moved.startOffset,
					endOffset: moved.endOffset,
					quoteExact: moved.quoteExact,
					quotePrefix: moved.quotePrefix,
					quoteSuffix: moved.quoteSuffix,
					chapterTitle: moved.chapterTitle
				)
			}
			for orphanedID in report.orphanedIDs {
				await account.markAnnotationOrphaned(annotationID: orphanedID, at: Date())
			}
		}
	}

	/// Scrolls to and briefly flashes the annotation's highlight via annotations.js.
	/// That file is cross-platform and exposes plain-argument functions on the global
	/// `Annotations` object, so no base64 encoding is needed for a single ID (unlike
	/// main_ios.js's scrollToHeading). Fire-and-forget; no-op if the mark isn't in the DOM.
	func scrollToAnnotation(annotationID: String) {
		scrollJumpHistory.append(Double(windowScrollY))
		let escaped = annotationID.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
		webView?.evaluateJavaScript("Annotations.scrollToAnnotation(\"\(escaped)\")") { _, error in
			if let error {
				Self.logger.error("scrollToAnnotation: Annotations.scrollToAnnotation() JS call failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	/// Resolves when this controller's page finishes loading. Used by
	/// ArticleViewController.navigateToAnnotation: article selection resolves well
	/// before the new controller's didFinish, and the mark to scroll to doesn't exist
	/// until then. If the page already loaded, this waits for the next load rather
	/// than hanging, since callers want the result of a navigation.
	func awaitNextPageLoad() async {
		await withCheckedContinuation { continuation in
			nextPageLoadContinuations.append(continuation)
		}
	}

	/// Resumes every pending awaitNextPageLoad() caller; called from webView(_:didFinish:).
	/// Storage is a stored property on the class, since extensions can't add them.
	func resumeAwaitingPageLoads() {
		let continuations = nextPageLoadContinuations
		nextPageLoadContinuations = []
		for continuation in continuations {
			continuation.resume()
		}
	}

	/// annotations.js reports new selections (with a rect) and selection-cleared events
	/// (`{cleared: true}`) through this handler. Behavior depends on
	/// annotationCreationMethod, read fresh (see initAnnotations()):
	///  - .popup: a non-empty selection presents HighlightColorPopover; `cleared` is ignored.
	///  - .nativeMenu: never presents the popover. Tracks whether a highlightable
	///    selection exists (currentSelectionRect), exposed via isSelectionHighlightable
	///    so buildMenu(with:) knows whether to offer "Highlight". `cleared` resets it to nil.
	///  - .off: shouldn't fire (annotations.js doesn't wire selectionchange), but a stale
	///    message after a mid-session mode change is ignored.
	func textWasSelected(body: [String: Any]?) {
		guard let body else { return }

		if body["cleared"] as? Bool == true {
			currentSelectionRect = nil
			return
		}

		guard let webView,
			  let x = body["x"] as? Double,
			  let y = body["y"] as? Double,
			  let width = body["width"] as? Double,
			  let height = body["height"] as? Double else {
			return
		}

		// Same safe-area offset and conversion as showFullScreenImage: the JS rect is in
		// web content coordinates, not this controller's.
		let adjustedY = CGFloat(y) + webView.safeAreaInsets.top
		let rect = CGRect(x: CGFloat(x), y: adjustedY, width: CGFloat(width), height: CGFloat(height))
		let convertedRect = webView.convert(rect, to: view)

		switch AppDefaults.shared.annotationCreationMethod {
		case .popup:
			presentHighlightColorPopover(sourceRect: convertedRect)
		case .nativeMenu:
			// No popover; just record that a highlightable selection exists. buildMenu(with:)
			// reads isSelectionHighlightable when the system next rebuilds its menu.
			currentSelectionRect = convertedRect
		case .off:
			break
		}
	}

	private func presentHighlightColorPopover(sourceRect: CGRect) {
		let popover = HighlightColorPopover(
			onSelectColor: { [weak self] color in
				self?.dismiss(animated: true)
				self?.saveHighlightFromSelection(color: color)
			}
		)

		let hostingController = UIHostingController(rootView: popover)
		hostingController.modalPresentationStyle = .popover
		// Sized for 3 swatches (3*28 + 2*14 + 2*16 = 144); fewer just leave it slightly
		// wider than its content, since SwiftUI centers the HStack.
		hostingController.preferredContentSize = CGSize(width: 144, height: 56)
		if let presentationController = hostingController.popoverPresentationController {
			presentationController.sourceView = view
			// Defensive clamp: if sourceRect falls outside view.bounds (a short selection's
			// small rect triggered this), UIPopoverPresentationController silently never
			// presents. Clamping anchors at the nearest valid edge instead. Independent of
			// the full-screen top inset handling in hideBars().
			presentationController.sourceRect = sourceRect.intersects(view.bounds)
				? sourceRect
				: sourceRect.clamped(toBounds: view.bounds)
			presentationController.permittedArrowDirections = [.up, .down]
			presentationController.delegate = self
		}
		present(hostingController, animated: true)
	}

	/// Calls annotations.js's addHighlightFromSelection to resolve the live selection
	/// into a selector and draw the highlight, then persists it. Does nothing if the
	/// selection didn't survive (popover dismissed, scrolled, etc.); there is no stale
	/// selector to fall back on, since the live selection is the only authority.
	///
	/// Save-only for both callers (popup swatch tap, native menu "Highlight"). A note
	/// is added later by tapping the mark, which routes to annotationWasTapped.
	private func saveHighlightFromSelection(color: Annotation.Color) {
		guard let article, let account = article.account else { return }

		let annotationID = UUID().uuidString
		let args: [String: String] = ["annotationID": annotationID, "color": color.rawValue]
		guard let argsJSON = try? JSONSerialization.data(withJSONObject: args) else { return }
		let encodedArgs = argsJSON.base64EncodedString()

		webView?.evaluateJavaScript("Annotations.addHighlightFromSelection(\"\(encodedArgs)\")") { [weak self] result, error in
			guard self != nil else { return }
			if let error {
				Self.logger.error("saveHighlightFromSelection: addHighlightFromSelection() JS call failed: \(error.localizedDescription, privacy: .public)")
				return
			}
			guard let b64 = result as? String, let data = Data(base64Encoded: b64) else {
				Self.logger.error("saveHighlightFromSelection: addHighlightFromSelection() returned an unexpected result type or invalid base64")
				return
			}
			guard let selector = try? JSONDecoder().decode(AnnotationSelector.self, from: data) else {
				// Not necessarily an error -- addHighlightFromSelection legitimately
				// returns base64("null") when the selection didn't survive.
				return
			}

			let now = Date()
			let annotation = Annotation(
				annotationID: selector.annotationID,
				articleID: article.articleID,
				bookKey: nil, // resolved from articleID at save time -- see ArticlesTable.saveAnnotationAsync
				quoteExact: selector.quoteExact,
				quotePrefix: selector.quotePrefix,
				quoteSuffix: selector.quoteSuffix,
				rootSelector: selector.rootSelector,
				startOffset: selector.startOffset,
				endOffset: selector.endOffset,
				color: color,
				note: nil,
				chapterTitle: selector.chapterTitle,
				createdAt: now,
				updatedAt: now
			)

			Task {
				await account.saveAnnotation(annotation)
			}
		}
	}

	/// The person tapped an existing highlight: open its note editor
	/// (creating one if this highlight has no note yet).
	func annotationWasTapped(body: [String: Any]?) {
		guard let article, let account = article.account,
			  let body, let annotationID = body["annotationID"] as? String else {
			return
		}

		Task {
			let annotations = await account.fetchAnnotations(forArticleID: article.articleID)
			guard let annotation = annotations.first(where: { $0.annotationID == annotationID }) else { return }
			self.openNoteEditor(for: annotation)
		}
	}

	/// "Highlight" chosen from the native selection menu (.nativeMenu mode). Reuses
	/// the popup's save path against the still-live selection (the system menu doesn't
	/// clear it), with the default color since there is no picker in this mode. See
	/// PreloadedWebView.buildMenu.
	func nativeMenuHighlightWasTapped() {
		saveHighlightFromSelection(color: AppDefaults.shared.defaultAnnotationColor)
	}

	/// Presents the note-editor half-sheet; a fresh highlight's mark tap and an
	/// existing <mark> tap both converge here.
	private func openNoteEditor(for annotation: Annotation) {
		guard let article, let account = article.account else { return }

		let editorView = AnnotationEditorView(
			annotation: annotation,
			onSave: { [weak self] note, color, editedText, keepHighlight in
				self?.saveNoteEdit(annotation: annotation, note: note, color: color, account: account)
				if let editedText {
					self?.saveTextEdit(annotation: annotation, replacementText: editedText, keepHighlight: keepHighlight, account: account)
				} else if keepHighlight != annotation.hasHighlight, annotation.originalText != nil {
					// Text unchanged but "keep highlight" moved on a row that already has an edit.
					// No offset shift or overlap is possible, so skip saveTextEdit's pipeline and
					// persist hasHighlight directly. The `originalText != nil` guard matters:
					// unchecking on a never-edited row would write hasHighlight == false with
					// originalText == nil, violating the Validity rule (docs/annotations.md, "Storage
					// shape"). That case is a no-op here rather than a silent delete or invalid row.
					self?.saveHasHighlightChange(annotation: annotation, hasHighlight: keepHighlight, account: account)
				}
			},
			onDelete: { [weak self] in
				self?.deleteAnnotation(annotation, account: account)
			}
		)

		let hostingController = UIHostingController(rootView: editorView)
		if let sheet = hostingController.sheetPresentationController {
			sheet.detents = [.medium(), .large()]
			sheet.prefersGrabberVisible = true
		}
		present(hostingController, animated: true)
	}

	private func saveNoteEdit(annotation: Annotation, note: String?, color: Annotation.Color, account: Account) {
		let colorChanged = color != annotation.color
		let noteChanged = note != annotation.note

		if colorChanged {
			webView?.evaluateJavaScript("Annotations.updateAnnotationColor(\"\(annotation.annotationID)\", \"\(color.rawValue)\")") { _, error in
				if let error {
					Self.logger.error("saveNoteEdit: Annotations.updateAnnotationColor() JS call failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		}

		Task {
			if colorChanged {
				await account.updateAnnotationColor(annotationID: annotation.annotationID, color: color)
			}
			if noteChanged {
				await account.updateAnnotationNote(annotationID: annotation.annotationID, note: note)
			}
		}
	}

	/// Handles the "Edit text" field and "Keep highlight" checkbox from
	/// AnnotationEditorView (docs/annotations.md, "Manual edit UI"). Called only when
	/// the text actually changed.
	///
	/// Pipeline (docs/annotations.md, "Applying edits"): fetch the other annotations,
	/// ask annotations.js (computeTextEditPlan, non-mutating, against the live DOM) to
	/// check for overlap and compute shifted anchors, then persist this row's edit
	/// fields and each shifted row's new anchor via account.reanchorAnnotation in
	/// descending-offset order (write order matters for the same reason as
	/// TextReplacementOffsetShift). Finally loadAndRenderAnnotations() re-renders; the
	/// DOM mutation (applyTextEdit) happens there, not here.
	///
	/// An overlap shows a blocking alert and writes nothing.
	private func saveTextEdit(annotation: Annotation, replacementText: String, keepHighlight: Bool, account: Account) {
		guard let article else { return }
		let articleID = article.articleID
		let originalText = annotation.replacementText ?? annotation.quoteExact
		let replacementLength = replacementText.count

		// Validity rule (docs/annotations.md, "Storage shape"): hasHighlight == true OR
		// originalText != nil. AnnotationEditorView only calls this for a real text
		// change, so no extra guard is needed here.

		Task {
			let allAnnotations = await account.fetchAnnotations(forArticleID: articleID)
			let others = allAnnotations.filter { $0.annotationID != annotation.annotationID }

			let otherPayload = others.map { [
				"annotationID": $0.annotationID,
				"startOffset": $0.startOffset,
				"endOffset": $0.endOffset
			] as [String: Any] }

			let args: [String: Any] = [
				"annotationToEditID": annotation.annotationID,
				"startOffset": annotation.startOffset,
				"endOffset": annotation.endOffset,
				"replacementLength": replacementLength,
				"otherAnnotations": otherPayload,
				"rootSelector": annotation.rootSelector
			]
			guard let argsJSON = try? JSONSerialization.data(withJSONObject: args) else {
				Self.logger.error("saveTextEdit: failed to serialize computeTextEditPlan args")
				return
			}
			let encodedArgs = argsJSON.base64EncodedString()

			let plan: TextEditPlan
			do {
				let result = try await self.webView?.evaluateJavaScript("Annotations.computeTextEditPlanEncoded(\"\(encodedArgs)\")")
				guard let b64 = result as? String, let data = Data(base64Encoded: b64) else {
					Self.logger.error("saveTextEdit: computeTextEditPlanEncoded() returned an unexpected result type or invalid base64")
					return
				}
				guard let decoded = try? JSONDecoder().decode(TextEditPlan.self, from: data) else {
					Self.logger.error("saveTextEdit: failed to decode TextEditPlan from computeTextEditPlanEncoded() result")
					return
				}
				plan = decoded
			} catch {
				Self.logger.error("saveTextEdit: computeTextEditPlanEncoded() JS call failed: \(error.localizedDescription, privacy: .public)")
				return
			}

			if plan.status == "overlap" {
				self.presentTextEditOverlapAlert()
				return
			}

			// Write this row's edit fields first; its offsets don't change.
			await account.setAnnotationEditFields(
				annotationID: annotation.annotationID,
				hasHighlight: keepHighlight,
				originalText: originalText,
				replacementText: replacementText
			)

			// Persist shifted rows in descending offset order (see TextReplacementOffsetShift).
			let shiftedDescending = plan.shifted.sorted { $0.startOffset > $1.startOffset }
			for shifted in shiftedDescending {
				await account.reanchorAnnotation(
					annotationID: shifted.annotationID,
					startOffset: shifted.startOffset,
					endOffset: shifted.endOffset,
					quoteExact: shifted.quoteExact,
					quotePrefix: shifted.quotePrefix,
					quoteSuffix: shifted.quoteSuffix,
					chapterTitle: shifted.chapterTitle
				)
			}

			self.loadAndRenderAnnotations()
		}
	}

	/// Persists a `hasHighlight`-only change (checkbox flipped, text untouched).
	/// Bypasses saveTextEdit's plan pipeline: this row's anchor doesn't move, so there
	/// is no overlap to check and nothing to reanchor. originalText/replacementText
	/// carry through. The re-render wraps/unwraps the <mark> since renderAnnotations
	/// re-evaluates hasHighlight per row (docs/annotations.md, "Storage shape").
	private func saveHasHighlightChange(annotation: Annotation, hasHighlight: Bool, account: Account) {
		Task {
			await account.setAnnotationEditFields(
				annotationID: annotation.annotationID,
				hasHighlight: hasHighlight,
				originalText: annotation.originalText,
				replacementText: annotation.replacementText
			)
			self.loadAndRenderAnnotations()
		}
	}

	/// Blocking alert for the overlap case (docs/annotations.md, "Applying edits").
	private func presentTextEditOverlapAlert() {
		let alert = UIAlertController(
			title: NSLocalizedString("Can’t Edit This Text", comment: "Text-edit overlap alert title"),
			message: NSLocalizedString("This text is part of an existing highlight or edit. Remove or resize it first.", comment: "Text-edit overlap alert message"),
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: .default))
		present(alert, animated: true)
	}

	private func deleteAnnotation(_ annotation: Annotation, account: Account) {
		revertOrUnwrapAnnotationDOM(annotation)

		Task {
			await account.deleteAnnotation(annotationID: annotation.annotationID)
		}
	}

	/// Reverts the live DOM only when the row belongs to this web view's
	/// currently displayed article. Persistence remains owned by the caller.
	func revertOrUnwrapAnnotationDOM(_ annotation: Annotation) {
		if let originalText = annotation.originalText {
			// A text-edit row: applyTextEdit already mutated the DOM at render time, so
			// unwrapping alone would leave the replacement text. Rows after the edit were
			// shifted by its length delta when it was saved, so shift them back first
			// (computeRevertPlan reads the live, still-edited DOM), then let
			// revertTextEdit restore originalText and unwrap (see annotations.js).
			Task {
				await self.persistRevertShift(for: annotation, originalText: originalText)
				self.revertTextEditInDOM(annotation, originalText: originalText)
			}
		} else {
			// Highlight-only row: the text was never touched, so unwrap the <mark> and
			// normalize the text nodes (see annotations.js).
			webView?.evaluateJavaScript("Annotations.removeAnnotationHighlight(\"\(annotation.annotationID)\")") { _, error in
				if let error {
					Self.logger.error("deleteAnnotation: Annotations.removeAnnotationHighlight() JS call failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		}

	}

	private func revertTextEditInDOM(_ annotation: Annotation, originalText: String) {
		let args: [String: String] = ["annotationID": annotation.annotationID, "originalText": originalText]
		guard let argsJSON = try? JSONSerialization.data(withJSONObject: args) else { return }
		let encodedArgs = argsJSON.base64EncodedString()

		webView?.evaluateJavaScript("Annotations.revertTextEdit(\"\(encodedArgs)\")") { _, error in
			if let error {
				Self.logger.error("deleteAnnotation: Annotations.revertTextEdit() JS call failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	/// Inverse of saveTextEdit's shift (docs/annotations.md, "Reverting an edit"): asks
	/// annotations.js (computeRevertPlan, non-mutating, against the live DOM that still
	/// shows the replacement) where every row after the edit moves back to, and persists
	/// each via account.reanchorAnnotation. Any failure or a "mismatch" status writes
	/// nothing; renderAnnotations' quote fallback then remains the safety net.
	private func persistRevertShift(for annotation: Annotation, originalText: String) async {
		guard let account = article?.account, let webView else { return }
		let articleID = annotation.articleID

		let others = await account.fetchAnnotations(forArticleID: articleID)
			.filter { $0.annotationID != annotation.annotationID }
		let otherPayload = others.map { [
			"annotationID": $0.annotationID,
			"startOffset": $0.startOffset,
			"endOffset": $0.endOffset
		] as [String: Any] }

		let args: [String: Any] = [
			"annotationID": annotation.annotationID,
			"startOffset": annotation.startOffset,
			"originalText": originalText,
			"replacementText": annotation.replacementText ?? "",
			"otherAnnotations": otherPayload,
			"rootSelector": annotation.rootSelector
		]
		guard let argsJSON = try? JSONSerialization.data(withJSONObject: args) else {
			Self.logger.error("deleteAnnotation: failed to serialize computeRevertPlan args")
			return
		}
		let encodedArgs = argsJSON.base64EncodedString()

		let plan: TextEditPlan
		do {
			let result = try await webView.evaluateJavaScript("Annotations.computeRevertPlanEncoded(\"\(encodedArgs)\")")
			guard let b64 = result as? String,
				  let data = Data(base64Encoded: b64),
				  let decoded = try? JSONDecoder().decode(TextEditPlan.self, from: data) else {
				Self.logger.error("deleteAnnotation: computeRevertPlanEncoded() returned an unexpected result")
				return
			}
			plan = decoded
		} catch {
			Self.logger.error("deleteAnnotation: computeRevertPlanEncoded() JS call failed: \(error.localizedDescription, privacy: .public)")
			return
		}

		guard plan.status == "ok" else {
			Self.logger.info("deleteAnnotation: revert plan status \(plan.status, privacy: .public); leaving other rows to the quote fallback")
			return
		}

		// Same descending order as saveTextEdit.
		for shifted in plan.shifted.sorted(by: { $0.startOffset > $1.startOffset }) {
			await account.reanchorAnnotation(
				annotationID: shifted.annotationID,
				startOffset: shifted.startOffset,
				endOffset: shifted.endOffset,
				quoteExact: shifted.quoteExact,
				quotePrefix: shifted.quotePrefix,
				quoteSuffix: shifted.quoteSuffix,
				chapterTitle: shifted.chapterTitle
			)
		}
	}

}

// MARK: - UIPopoverPresentationControllerDelegate

extension WebViewController: UIPopoverPresentationControllerDelegate {

	func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
		// Force a true popover on compact width, where UIKit would adapt to a sheet.
		.none
	}

}

// MARK: - PreloadedWebViewAnnotationDelegate

extension WebViewController: PreloadedWebViewAnnotationDelegate {

	/// Backed by currentSelectionRect, which is only set in .nativeMenu mode, so this
	/// is false by construction in .popup/.off.
	var isSelectionHighlightable: Bool {
		currentSelectionRect != nil
	}

}
