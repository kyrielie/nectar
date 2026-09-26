//
//  BookKeyPrefix.swift
//  RSParser
//
//  The three bookKey string prefixes, single-sourced. Previously duplicated
//  as separate literals in ParsedItem, the SQL CASE in
//  AmbrosiaSQLiteImportTable/ArticlesDatabase, AO3ChapterFetcher's private
//  constants, and a raw literal in WebViewController. RSParser owns them
//  because AO3Kit depends on RSParser (not the reverse), so RSParser is the
//  only module every consumer can reach.
//

public enum BookKeyPrefix {
	public static let ao3Work = "ao3-work:"
	public static let ao3Series = "ao3-series:"
	public static let calibreSeries = "calibre-series:"
}
