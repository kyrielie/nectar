//
//  ArticleStatus+Database.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/3/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Foundation
import RSDatabase
import RSDatabaseObjC
import Articles

extension ArticleStatus {

	convenience init(articleID: String, dateArrived: Date, row: FMResultSet) {
		let read = row.bool(forColumn: DatabaseKey.read)
		let starred = row.bool(forColumn: DatabaseKey.starred)
		let readingProgress = row.columnIsNull(DatabaseKey.readingProgress) ? nil : row.double(forColumn: DatabaseKey.readingProgress)
		let loved = row.bool(forColumn: DatabaseKey.loved)
		let lastOpenedAt = row.columnIsNull(DatabaseKey.lastOpenedAt) ? nil : row.date(forColumn: DatabaseKey.lastOpenedAt)

		self.init(articleID: articleID, read: read, starred: starred, dateArrived: dateArrived, readingProgress: readingProgress, loved: loved, lastOpenedAt: lastOpenedAt)
	}

	func databaseDictionary() -> DatabaseDictionary {
		return [DatabaseKey.articleID: articleID, DatabaseKey.read: read, DatabaseKey.starred: starred, DatabaseKey.dateArrived: dateArrived, DatabaseKey.loved: loved]
	}
}
