import Articles
import ArticlesDatabase
import RSParser

@MainActor public protocol AO3ArticleUpdating: AnyObject {
	func updateAsync(feedID: String, parsedItems: Set<ParsedItem>, deleteOlder: Bool) async -> ArticleChanges
	func sendNotificationAbout(_ articleChanges: ArticleChanges)
}

@MainActor public protocol AO3SearchFeedPageTracking: AnyObject {
	var feedID: String { get }
	var url: String { get }
	var ao3SearchFetchedPages: Set<Int>? { get set }
	var ao3SearchTotalPages: Int? { get set }
}
