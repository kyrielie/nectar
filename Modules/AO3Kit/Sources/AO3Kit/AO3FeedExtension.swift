import Foundation
import RSParser

public struct AO3FeedExtension: AO3FeedItemExtending {
	public init() {}

	public func extractedItem(fromSummaryHTML summaryHTML: String, permalink: String?, language: String?) -> AO3SummaryExtractionResult? {
		guard let result = AO3SummaryExtractor.extract(fromSummaryHTML: summaryHTML) else { return nil }
		return AO3SummaryExtractionResult(
			cleanedSummaryHTML: result.cleanedSummaryHTML,
			wordCount: result.wordCount,
			chapterCurrent: result.chapterCurrent,
			chapterTotal: result.chapterTotal,
			isComplete: result.isComplete,
			language: result.language ?? language,
			fandoms: result.fandoms,
			ratings: result.ratings,
			warnings: result.warnings,
			categories: result.categories,
			characters: result.characters,
			relationships: result.relationships,
			additionalTags: result.additionalTags,
			series: result.series,
			ao3WorkID: Self.ao3WorkID(fromPermalink: permalink))
	}

	/// The work id, but only when `permalink` is on one of AO3's own hosts
	/// (`AO3Link.recognizedHosts`). A work id becomes an `ao3-work:` bookKey
	/// that `AO3ChapterFetcher` turns into a live request to
	/// archiveofourown.org. Without the host check, an AO3-shaped feed entry
	/// from any other host (a mirror, a proxy, a test fixture) would trigger
	/// a fetch of whichever real work happens to share that number.
	private static func ao3WorkID(fromPermalink permalink: String?) -> String? {
		AO3Link.workID(fromPermalink: permalink)
	}

	public func shouldExclude(_ item: ParsedItem) -> Bool {
		AO3IgnoreList.shouldExclude(item)
	}
}
