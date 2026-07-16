//
//  DatabaseTable.swift
//  RSDatabase
//
//  Created by Brent Simmons on 7/16/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import RSDatabaseObjC
import os

public protocol DatabaseTable {

	var name: String { get }
}

public extension DatabaseTable {

	// MARK: Fetching

	func selectRowsWhere(key: String, equals value: Any, in database: FMDatabase) -> FMResultSet? {

		return database.rs_selectRowsWhereKey(key, equalsValue: value, tableName: name)
	}

	func selectRowsWhere(key: String, inValues values: [Any], in database: FMDatabase) -> FMResultSet? {
		if values.isEmpty {
			return nil
		}
		return database.rs_selectRowsWhereKey(key, inValues: values, tableName: name)
	}

	// MARK: Deleting

	func deleteRowsWhere(key: String, equalsAnyValue values: [Any], in database: FMDatabase) {
		if values.isEmpty {
			return
		}
		database.rs_deleteRowsWhereKey(key, inValues: values, tableName: name)
	}

	// MARK: Updating

	func updateRowsWithValue(_ value: Any, valueKey: String, whereKey: String, matches: [Any], database: FMDatabase) {
		_ = database.rs_updateRows(withValue: value, valueKey: valueKey, whereKey: whereKey, inValues: matches, tableName: self.name)
	}

	func updateRowsWithDictionary(_ dictionary: DatabaseDictionary, whereKey: String, matches: Any, database: FMDatabase) {
		_ = database.rs_updateRows(with: dictionary, whereKey: whereKey, equalsValue: matches, tableName: self.name)
	}

	// MARK: Saving

	func insertRows(_ dictionaries: [DatabaseDictionary], insertType: RSDatabaseInsertType, in database: FMDatabase) {
		// Diagnostic: previously discarded rs_insertRow's per-row
		// success/failure result (`_ = ...`), so any silently-failing
		// INSERT here -- constraint violation, type mismatch, an
		// .orIgnore conflict, etc. -- would vanish without a trace for
		// every caller of this shared helper (including StatusesTable,
		// which uses insertType: .orIgnore). Log a count and sample
		// failing rows so a shortfall shows up regardless of which
		// table called in.
		var failedCount = 0
		var firstFailedKeys = [String]()
		for oneDictionary in dictionaries {
			let didSucceed = database.rs_insertRow(with: oneDictionary, insertType: insertType, tableName: self.name)
			if !didSucceed {
				failedCount += 1
				if firstFailedKeys.count < 5 {
					let keyDescription = oneDictionary.keys.sorted().map { "\($0)=\(oneDictionary[$0] ?? "nil")" }.joined(separator: ",")
					firstFailedKeys.append(keyDescription)
				}
			}
		}
		if failedCount > 0 {
			let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "unknown", category: "DatabaseTable")
			logger.warning("DatabaseTable: insertRows table=\(self.name, privacy: .public) attempted=\(dictionaries.count, privacy: .public) failed=\(failedCount, privacy: .public) insertType=\(String(describing: insertType), privacy: .public) lastError=\(database.lastErrorMessage(), privacy: .public) sampleFailedRows=\(firstFailedKeys.joined(separator: " | "), privacy: .public)")
		}
	}

	func insertRow(_ rowDictionary: DatabaseDictionary, insertType: RSDatabaseInsertType, in database: FMDatabase) {
		insertRows([rowDictionary], insertType: insertType, in: database)
	}

	// MARK: Counting

	func numberWithSQLAndParameters(_ sql: String, _ parameters: [Any], in database: FMDatabase) -> Int {
		guard let resultSet = database.executeQuery(sql, withArgumentsIn: parameters), resultSet.next() else {
			return 0
		}
		return Int(resultSet.int(forColumnIndex: 0))
	}

	// MARK: Columns

	func containsColumn(_ columnName: String, in database: FMDatabase) -> Bool {
		if let resultSet = database.executeQuery("select * from \(name) limit 1;", withArgumentsIn: nil) {
			if let columnMap = resultSet.columnNameToIndexMap {
				if columnMap[columnName.lowercased()] != nil {
					return true
				}
			}
		}
		return false
	}
}
