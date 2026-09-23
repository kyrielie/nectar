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
			ao3WorkID: AO3SummaryExtractor.ao3WorkID(fromPermalink: permalink))
	}

	public func shouldExclude(_ item: ParsedItem) -> Bool {
		AO3IgnoreList.shouldExclude(item)
	}
}
