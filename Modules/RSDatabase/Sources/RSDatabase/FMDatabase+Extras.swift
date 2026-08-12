//
//  FMDatabase+Extras.swift
//
//
//  Created by Brent Simmons on 3/10/24.
//

import Foundation
import RSDatabaseObjC
import os

public extension FMDatabase {

	static func openAndSetUpDatabase(path: String) -> FMDatabase {
		let database = FMDatabase(path: path)!

		database.open()
		// All databases are single-connection and serialized — WAL gains us nothing
		// and produces extra -wal/-shm files that bloat on disk.
		database.executeStatements("PRAGMA journal_mode = DELETE;")
		database.executeStatements("PRAGMA synchronous = 1;")
		database.setShouldCacheStatements(true)

		return database
	}

	func executeUpdateInTransaction(_ sql: String, withArgumentsIn parameters: [Any]? = nil) {
		beginTransaction()
		guard executeUpdate(sql, withArgumentsIn: parameters) else {
			rollback()
			return
		}
		commit()
	}

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FMDatabase")

	func vacuum() {
		let path = databasePath() ?? "unknown"
		let start = Date()
		executeStatements("vacuum;")
		let duration = Date().timeIntervalSince(start)
		Self.logger.debug("VACUUM \(path, privacy: .public) took \(duration, format: .fixed(precision: 4), privacy: .public) seconds")
	}

	/// Vacuum if at least `daysBetweenVacuums` have passed since last time.
	/// The last vacuum date is stored in the database.
	func vacuumIfNeeded(daysBetweenVacuums: Int = RSDatabaseInfoTable.defaultDaysBetweenVacuums) {
		RSDatabaseInfoTable.createTableIfNeeded(database: self)

		if let lastVacuumDate = RSDatabaseInfoTable.lastVacuumDate(database: self) {
			let secondsBetweenVacuums = TimeInterval(daysBetweenVacuums) * 24 * 60 * 60
			if Date().timeIntervalSince(lastVacuumDate) < secondsBetweenVacuums {
				return
			}
		}

		vacuum()
		RSDatabaseInfoTable.setLastVacuumDate(Date(), database: self)
	}

	func runCreateStatements(_ statements: String) {
		statements.enumerateLines { (line, stop) in
			if line.lowercased().hasPrefix("create") {
				self.executeStatements(line)
			}
			stop = false
		}
	}

	func insertRows(_ dictionaries: [DatabaseDictionary], insertType: RSDatabaseInsertType, tableName: String) {
		for dictionary in dictionaries {
			insertRow(dictionary, insertType: insertType, tableName: tableName)
		}
	}

	func insertRow(_ dictionary: DatabaseDictionary, insertType: RSDatabaseInsertType, tableName: String) {
		rs_insertRow(with: dictionary, insertType: insertType, tableName: tableName)
	}

	func updateRowsWithValue(_ value: Any, valueKey: String, whereKey: String, equalsAnyValue values: [Any], tableName: String) {
		rs_updateRows(withValue: value, valueKey: valueKey, whereKey: whereKey, inValues: values, tableName: tableName)
	}

	func updateRowsWithValue(_ value: Any, valueKey: String, whereKey: String, equals match: Any, tableName: String) {
		updateRowsWithValue(value, valueKey: valueKey, whereKey: whereKey, equalsAnyValue: [match], tableName: tableName)
	}

	func updateRowsWithDictionary(_ dictionary: [String: Any], whereKey: String, equals value: Any, tableName: String) {
		rs_updateRows(with: dictionary, whereKey: whereKey, equalsValue: value, tableName: tableName)
	}

	func deleteRowsWhere(key: String, equalsAnyValue values: [Any], tableName: String) {
		rs_deleteRowsWhereKey(key, inValues: values, tableName: tableName)
	}

	func deleteRowsWhere(key: String, equals value: Any, tableName: String) {
		rs_deleteRowsWhereKey(key, equalsValue: value, tableName: tableName)
	}

	func selectRowsWhere(key: String, equalsAnyValue values: [Any], tableName: String) -> FMResultSet? {
		rs_selectRowsWhereKey(key, inValues: values, tableName: tableName)
	}

	func count(sql: String, parameters: [Any]?, tableName: String) -> Int? {
		guard let resultSet = executeQuery(sql, withArgumentsIn: parameters) else {
			return nil
		}

		let count = resultSet.intWithCountResult()
		return count
	}

	/// Reads this connection's "main" schema `PRAGMA user_version`, defaulting
	/// to 0 (SQLite's own default for a database that's never set it) if the
	/// query fails outright. Unqualified `PRAGMA user_version` always
	/// addresses "main", not any ATTACH DATABASE'd schema -- see
	/// `ArticlesDatabase.currentSchemaVersion`'s doc comment for why that
	/// matters here.
	func userVersion() -> Int32 {
		guard let resultSet = executeQuery("PRAGMA user_version;", withArgumentsIn: nil) else {
			return 0
		}
		defer { resultSet.close() }
		guard resultSet.next() else {
			return 0
		}
		return resultSet.int(forColumnIndex: 0)
	}

	/// Sets this connection's "main" schema `PRAGMA user_version`. `PRAGMA`
	/// doesn't accept bound parameters, and the value here is always an
	/// internal constant (never user/network input), so string interpolation
	/// is safe.
	func setUserVersion(_ version: Int32) {
		executeStatements("PRAGMA user_version = \(version);")
	}
}
