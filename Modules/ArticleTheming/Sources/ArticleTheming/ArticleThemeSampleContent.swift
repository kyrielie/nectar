//
//  ArticleThemeSampleContent.swift
//  ArticleTheming
//
//  The sample article shared by the Settings preview and the theme color
//  probe, so both render the same markup through a theme's own template.
//  Moved out of `ArticleThemePreviewWebView`.
//

import Foundation

public enum ArticleThemeSampleContent {

	/// A fixed, non-resolving base URL for sample pages.
	public static let baseURLString = "https://example.invalid/"

	/// 1x1 transparent GIF, used in place of a real feed icon so `<img src="[[avatar_src]]">`
	/// doesn't show a broken-image placeholder in themes that render one.
	public static let transparentPixelDataURL = "data:image/gif;base64,R0lGODlhAQABAAAAACwAAAAAAQABAAA="

	/// Used only if a theme has no `template.html`, so a preview never renders blank.
	public static let fallbackTemplate = """
	<article>
	    <div class="articleTitle"><h1><a href="#">[[title]]</a></h1></div>
	    <div class="articleDatelineTitle"><a href="#">[[datetime_medium]]</a></div>
	    <div id="bodyContainer" class="articleBody">[[body]]</div>
	</article>
	"""

	/// Matches the sample article shown in Settings → Timeline Layout's preview
	/// (`TimelineCustomizerCollectionViewController.previewArticle`), so the two
	/// settings screens don't show two different fictional excerpts side by side.
	///
	/// Ordered the way AO3 itself lays out a work's preface -- the tag/stats
	/// preface block first, then Summary, then Notes, then (for a
	/// multi-chapter work) each chapter's own heading -- confirmed against a
	/// real fetched/exported work: `#ao3SyntheticPreface`'s `dl.tags` sits
	/// above `.summary.module`, which precedes `.notes.module`, both above
	/// the chapters themselves. A theme that only styles one of
	/// `.summary.module`/`.notes.module` (both are vanishingly rare to omit,
	/// but themes vary) would otherwise look identical in this preview to one
	/// that styles both.
	///
	/// The preface block itself only carries Warnings and Chapters -- not the
	/// full AO3 row set (Rating/Category/Fandom/Relationships/Characters/
	/// Additional Tags/etc) -- since this screen is demonstrating `dl.tags`
	/// grid styling (see `AO3PrefaceRenderer`/core.css), not standing in for
	/// fandom chrome the way a full tag block would.
	/// Wraps the sample chapter's paragraphs in the same
	/// `div.userstuff.module[role="article"]` structure
	/// `AO3ChapterHTMLExtractor` produces for real fetched/imported chapter
	/// text (see `AO3ChapterHTMLExtractor.swift`), rather than leaving them
	/// as bare direct children of `#bodyContainer`. A theme's own CSS/JS that
	/// locates "the opening paragraph" by direct-child position (e.g.
	/// `.articleBody > p:first-of-type`) or by naive first-`<p>`-in-document
	/// selection (which would otherwise match the Summary's `<p>` above,
	/// document-order-earlier than the real chapter text) looked correct
	/// against a flatter sample body here but broke against real content --
	/// this wrapper is what makes that class of bug visible in this preview
	/// instead of only in a real article.
	public static let sampleBody = """
	<div id="ao3SyntheticPreface"><dl class="tags">
	<dt>Warnings:</dt><dd>No Archive Warnings Apply</dd>
	<dt>Chapters:</dt><dd>2/2</dd>
	</dl></div>
	<div class="summary module">
	<h3 class="heading">Summary:</h3>
	<blockquote class="userstuff">
	<p>A short work summary, so summary styling has something to show against.</p>
	</blockquote>
	</div>
	<div class="notes module">
	<h3 class="heading">Notes:</h3>
	<blockquote class="userstuff">
	<p>A short author's note, so notes styling has something to show against.</p>
	</blockquote>
	</div>
	<div class="chapter preface group">
	<h3 class="title">Chapter 2: A Sample Heading</h3>
	</div>
	<div class="userstuff module" role="article">
	<p>Bree was the chief village of Bree-land, a small country a few miles broad whose chief claim to fame was its aluminum siding industry.</p>
	<p>The Men of Bree were cheerful and independent: they belonged to nobody but themselves. In the lands beyond Bree there were <a href="#">mysterious wanderers</a>.</p>
	</div>
	"""

	/// The macro values a theme's `template.html` receives for the sample article.
	/// `feed_link_title` is empty when `showFeedName` is false, matching
	/// `ArticleRenderer.articleSubstitutions()`.
	public static func substitutions(showFeedName: Bool = true) -> [String: String] {
		[
			"title": "At The Sign Of The Prancing Pony",
			"preferred_link": "#",
			"external_link_label": NSLocalizedString("Link:", comment: "Link"),
			"external_link_stripped": "example.com",
			"external_link": "#",
			"feed_link_title": showFeedName ? "Sample Feed" : "",
			"feed_link": "#",
			"byline": "by J. R. R. Tolkien",
			"avatar_src": transparentPixelDataURL,
			"dateline_style": "articleDatelineTitle",
			"datetime_long": "June 9, 2026",
			"datetime_medium": "Jun 9, 2026",
			"datetime_short": "6/9/26",
			"date_long": "June 9, 2026",
			"date_medium": "Jun 9, 2026",
			"date_short": "6/9/26",
			"time_long": "12:00:00 PM",
			"time_medium": "12:00 PM",
			"time_short": "12:00 PM",
			"body": sampleBody
		]
	}
}
