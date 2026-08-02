//
//  RSSItem.swift
//  RSParser
//
//  Created by Brent Simmons on 2026-04-24.
//

import Foundation
import RSCore

/// Feed item shared by the RSS and Atom parsers.
final class RSSItem {

	var guid: String?
	var title: String?
	var body: String?
	var summary: String?
	var markdown: String?
	var link: String?        // External link
	var permalink: String?   // URL of the item itself
	var language: String?
	var datePublished: Date?
	var dateModified: Date?
	var authors: Set<ParsedAuthor> = []
	var attachments: Set<ParsedAttachment> = []

	/// Returns `guid` if present. Otherwise MD5-hashes available properties
	/// to build the most likely stable ID.
	///
	/// Don't change this without a super-good reason! It would mean article IDs
	/// would no longer match, and people would have many duplicates.
	var uniqueID: String {
		if let guid, !guid.isEmpty {
			return guid
		}

		let datePublishedString: String?
		if let datePublished {
			datePublishedString = String(format: "%.0f", datePublished.timeIntervalSince1970)
		} else {
			datePublishedString = nil
		}

		var s = ""
		if let permalink, !permalink.isEmpty, let datePublishedString {
			s = permalink + datePublishedString
		} else if let link, !link.isEmpty, let datePublishedString {
			s = link + datePublishedString
		} else if let title, !title.isEmpty, let datePublishedString {
			s = title + datePublishedString
		} else if let datePublishedString {
			s = datePublishedString
		} else if let permalink, !permalink.isEmpty {
			s = permalink
		} else if let link, !link.isEmpty {
			s = link
		} else if let title, !title.isEmpty {
			s = title
		} else if let body, !body.isEmpty {
			s = body
		}
		return s.md5String
	}

	func toParsedItem(feedURL: String) -> ParsedItem {
		// AO3 tag/user feeds carry their metadata as machine-generated HTML
		// inside the summary itself. Try that extraction before falling back
		// to the generic "promote summary to contentHTML" behavior below --
		// on success, contentHTML is deliberately left nil (Workstream 2 of
		// the AO3 plan fills it in on demand) and the cleaned prose becomes
		// the summary.
		if let s = summary, !s.isEmpty, let result = AO3SummaryExtractor.extract(fromSummaryHTML: s) {
			return ParsedItem(
				syncServiceID: nil,
				uniqueID: uniqueID,
				feedURL: feedURL,
				url: permalink,
				externalURL: link,
				title: title,
				language: language,
				contentHTML: nil,
				contentText: nil,
				markdown: markdown,
				summary: result.cleanedSummaryHTML,
				imageURL: nil,
				bannerImageURL: nil,
				datePublished: datePublished,
				dateModified: dateModified,
				authors: authors.isEmpty ? nil : authors,
				tags: result.additionalTags.map { Set($0) },
				attachments: attachments.isEmpty ? nil : attachments,
				isAmbrosiaItem: false,
				wordCount: result.wordCount,
				chapterCurrent: result.chapterCurrent,
				chapterTotal: result.chapterTotal,
				isComplete: result.isComplete,
				fandoms: result.fandoms,
				relationships: result.relationships,
				characters: result.characters,
				ratings: result.ratings,
				warnings: result.warnings,
				categories: result.categories,
				series: result.series,
				ao3WorkID: AO3SummaryExtractor.ao3WorkID(fromPermalink: permalink)
			)
		}

		// If body is empty and summary has content,
		// promote summary to body and drop summary.
		var contentHTML = body
		var itemSummary = summary
		if contentHTML == nil || contentHTML?.isEmpty == true, let s = itemSummary, !s.isEmpty {
			contentHTML = s
			itemSummary = nil
		}

		return ParsedItem(
			syncServiceID: nil,
			uniqueID: uniqueID,
			feedURL: feedURL,
			url: permalink,
			externalURL: link,
			title: title,
			language: language,
			contentHTML: contentHTML,
			contentText: nil,
			markdown: markdown,
			summary: itemSummary,
			imageURL: nil,
			bannerImageURL: nil,
			datePublished: datePublished,
			dateModified: dateModified,
			authors: authors.isEmpty ? nil : authors,
			tags: nil,
			attachments: attachments.isEmpty ? nil : attachments
		)
	}
}
