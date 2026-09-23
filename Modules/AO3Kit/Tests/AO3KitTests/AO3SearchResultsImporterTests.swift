import XCTest
import Articles
import ArticlesDatabase
import RSParser
@testable import AO3Kit

@MainActor
final class AO3SearchResultsImporterTests: XCTestCase {
	final class FakeFeed: AO3SearchFeedPageTracking {
		let feedID = "test-feed"
		let url = "https://archiveofourown.org/works?work_search%5Bquery%5D=test"
		var ao3SearchFetchedPages: Set<Int>?
		var ao3SearchTotalPages: Int?
	}

	final class FakeAccount: AO3ArticleUpdating {
		var updateCount = 0
		var notificationCount = 0

		func updateAsync(feedID: String, parsedItems: Set<ParsedItem>, deleteOlder: Bool) async -> ArticleChanges {
			updateCount += 1
			return ArticleChanges()
		}

		func sendNotificationAbout(_ articleChanges: ArticleChanges) {
			notificationCount += 1
		}
	}

	private func html(workID: String, totalPages: Int? = nil) -> String {
		var value = """
		<html><head><title>Some Fandom - Works | Archive of Our Own</title></head><body>
		<li class="work-\(workID)"><h4 class="heading"><a href="/works/\(workID)">A Test Work</a> by <a rel="author" href="/users/author">author</a></h4></li>
		"""
		if let totalPages {
			value += "<ol class=\"pagination\"><li><a href=\"?page=1\">1</a></li><li><a href=\"?page=\(totalPages)\">\(totalPages)</a></li></ol>"
		}
		return value + "</body></html>"
	}

	func testImportUpdatesAndAdvancesPage() async {
		let feed = FakeFeed()
		let account = FakeAccount()
		feed.ao3SearchFetchedPages = [1, 2]

		let outcome = await AO3SearchResultsImporter.importFetchedPage(
			html: html(workID: "44444", totalPages: 9),
			feedURL: feed.url,
			feed: feed,
			account: account,
			advancePageTo: 4)

		guard case .imported(let count, _, _) = outcome else {
			return XCTFail("expected imported outcome")
		}
		XCTAssertEqual(count, 1)
		XCTAssertEqual(feed.ao3SearchFetchedPages, [1, 2, 4])
		XCTAssertEqual(feed.ao3SearchTotalPages, 9)
		XCTAssertEqual(account.updateCount, 1)
		XCTAssertEqual(account.notificationCount, 1)
	}

	func testNoAdvanceLeavesPagesUntouched() async {
		let feed = FakeFeed()
		let account = FakeAccount()
		feed.ao3SearchFetchedPages = [1, 2]

		_ = await AO3SearchResultsImporter.importFetchedPage(
			html: html(workID: "99999"),
			feedURL: feed.url,
			feed: feed,
			account: account,
			advancePageTo: nil)

		XCTAssertEqual(feed.ao3SearchFetchedPages, [1, 2])
	}
}
