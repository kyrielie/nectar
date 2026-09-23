import Foundation

public struct AO3SummaryExtractionResult: Sendable {
	public let cleanedSummaryHTML: String?
	public let wordCount: Int?
	public let chapterCurrent: Int?
	public let chapterTotal: Int?
	public let isComplete: Bool?
	public let language: String?
	public let fandoms: [String]?
	public let ratings: [String]?
	public let warnings: [String]?
	public let categories: [String]?
	public let characters: [String]?
	public let relationships: [String]?
	public let additionalTags: [String]?
	public let series: [ParsedSeriesEntry]?
	public let ao3WorkID: String?

	public init(cleanedSummaryHTML: String?, wordCount: Int?, chapterCurrent: Int?, chapterTotal: Int?, isComplete: Bool?, language: String?, fandoms: [String]?, ratings: [String]?, warnings: [String]?, categories: [String]?, characters: [String]?, relationships: [String]?, additionalTags: [String]?, series: [ParsedSeriesEntry]?, ao3WorkID: String?) {
		self.cleanedSummaryHTML = cleanedSummaryHTML
		self.wordCount = wordCount
		self.chapterCurrent = chapterCurrent
		self.chapterTotal = chapterTotal
		self.isComplete = isComplete
		self.language = language
		self.fandoms = fandoms
		self.ratings = ratings
		self.warnings = warnings
		self.categories = categories
		self.characters = characters
		self.relationships = relationships
		self.additionalTags = additionalTags
		self.series = series
		self.ao3WorkID = ao3WorkID
	}
}

public protocol AO3FeedItemExtending: Sendable {
	func extractedItem(fromSummaryHTML summaryHTML: String, permalink: String?, language: String?) -> AO3SummaryExtractionResult?
	func shouldExclude(_ item: ParsedItem) -> Bool
}

public enum AO3FeedExtensionPoint {
	public nonisolated(unsafe) static var provider: AO3FeedItemExtending?
}
