//
//  AO3PrefetchQueue.swift
//  Account
//
//  Nectar AO3 direct-reading support -- pacing/bounding for
//  AO3PrefetchNewWorksPreference's opt-in "fetch new works immediately"
//  path.
//
//  LocalAccountRefresher can finish updateAsync for several feeds
//  concurrently within one refresh pass (downloadFeeds is handed to
//  DownloadSession as a set, not walked one at a time), so pacing can't
//  live as a simple loop inside a single feed's completion handler --
//  it needs to be shared across every feed's newly-discovered AO3
//  articles for the whole pass. This actor is that shared point: every
//  candidate article from every feed funnels through enqueue(_:), and a
//  single drain loop fires fetchIfNeeded for them one at a time, spaced
//  by AO3ChapterFetcher.secondsBetweenAO3PagedRequests, the same pacing
//  constant AO3SeriesNavigator's own paged fetches use.
//
//  fetchIfNeeded itself is fire-and-forget and already carries its own
//  isStale/isAO3NetworkRequestAllowed/anti-hammering checks
//  (AO3ChapterFetcher.swift) -- this actor's only job is spacing out
//  *when* those calls happen and capping how many happen per refresh
//  cycle, not duplicating any of that logic.
//
import Foundation
import Articles

actor AO3PrefetchQueue {

	static let shared = AO3PrefetchQueue()

	/// Upper bound on how many prefetch fetches this actor will kick off
	/// per top-level refresh pass (see resetForNewRefreshCycle()) --
	/// deliberately conservative, same spirit as the removed background
	/// sweep's maxArticlesPerSweep. Chosen as roughly "a very active
	/// week's worth of new items across all feeds," not tuned against
	/// real subscription sizes yet.
	///
	/// Once this is hit, any articles still in `pending` are dropped,
	/// not carried over to the next cycle -- a first-time subscription
	/// to a very active feed falls back to today's open-time-only
	/// behavior for whatever didn't fit this pass, rather than this
	/// preference quietly turning into a slow full-backlog crawl across
	/// many refreshes. Carrying the remainder forward to the next cycle
	/// instead is the natural alternative if this trade turns out to be
	/// wrong in practice -- see docs/refresh-throttling.md for where this
	/// cap sits in the broader throttling picture.
	private static let maxArticlesPerRefreshCycle = 20

	private var pending: [Article] = []
	private var countThisCycle = 0
	private var isDraining = false

	/// Real pacing (AO3ChapterFetcher.secondsBetweenAO3PagedRequests, 5s)
	/// by default -- overridden down to near-zero in tests via
	/// setPacingIntervalForTesting(_:) so exercising the budget cap
	/// doesn't mean waiting out 20 real 5-second sleeps.
	private var pacingInterval: TimeInterval = AO3ChapterFetcher.secondsBetweenAO3PagedRequests

	/// Called once per top-level refresh pass, from LocalAccountRefresher.
	/// refreshFeeds, alongside its own newArticlesCount reset -- so a
	/// feed that refreshes often doesn't slowly exhaust a budget shared
	/// across unrelated refresh passes. Cheap no-op call when
	/// AO3PrefetchNewWorksPreference is off, since nothing is ever
	/// enqueued in that case.
	///
	/// Known gap: a full 20-item drain can take up to ~100s at real
	/// pacing (5s * 20), so a person who manually triggers another
	/// refresh before a large previous batch has finished draining will
	/// reset countThisCycle mid-drain -- the tail of the old batch then
	/// counts against the new cycle's budget instead of the one it was
	/// enqueued under. Not addressed here: the actual worst case (a few
	/// extra fetches borrowed from the next cycle) is minor next to the
	/// complexity of tracking per-enqueue cycle ownership, but worth
	/// knowing about if maxArticlesPerRefreshCycle or the pacing
	/// interval changes enough to make the overlap window larger.
	func resetForNewRefreshCycle() {
		countThisCycle = 0
	}

	/// Adds `articles` to the pending queue and starts draining if not
	/// already in progress. Safe to call from multiple concurrent feed
	/// completions -- actor isolation serializes access to `pending`.
	func enqueue(_ articles: [Article]) {
		guard !articles.isEmpty else {
			return
		}
		pending.append(contentsOf: articles)
		guard !isDraining else {
			return
		}
		isDraining = true
		Task {
			await drain()
		}
	}

	private func drain() async {
		defer {
			isDraining = false
		}
		while !pending.isEmpty, countThisCycle < Self.maxArticlesPerRefreshCycle {
			let article = pending.removeFirst()
			AO3ChapterFetcher.shared.fetchIfNeeded(for: article)
			countThisCycle += 1
			try? await Task.sleep(nanoseconds: UInt64(pacingInterval * 1_000_000_000))
		}
		pending.removeAll()
	}
}

extension AO3PrefetchQueue {

	/// Test-only accessors -- direct state inspection rather than
	/// inferring behavior from AO3ChapterFetcher's own side effects,
	/// mirroring AO3SeriesNavigatorTests' markWalkedForTesting-style
	/// seams.
	func pendingCountForTesting() -> Int {
		pending.count
	}

	func countThisCycleForTesting() -> Int {
		countThisCycle
	}

	func isDrainingForTesting() -> Bool {
		isDraining
	}

	/// Shrinks the delay between fetches so a test can drive the queue
	/// past its per-cycle budget without waiting out real 5-second
	/// sleeps. Does not affect maxArticlesPerRefreshCycle itself.
	func setPacingIntervalForTesting(_ interval: TimeInterval) {
		pacingInterval = interval
	}

	/// Full reset for test isolation -- clears pending/countThisCycle/
	/// isDraining and restores real pacing, since `shared` is a
	/// process-lifetime singleton and tests otherwise leak state into
	/// each other depending on run order (same concern
	/// AO3ChapterFetcherTests's makeArticle doc comment calls out for
	/// AO3ChapterFetcher.shared.attemptDates).
	func resetForTesting() {
		pending.removeAll()
		countThisCycle = 0
		isDraining = false
		pacingInterval = AO3ChapterFetcher.secondsBetweenAO3PagedRequests
	}
}
