//
//  SQLiteIDList.swift
//  RSDatabase
//
//  Encodes ID collections as a single JSON array parameter for SQLite's
//  `json_each(?)` table-valued function, avoiding `SQLITE_MAX_VARIABLE_NUMBER`
//  limits on large `IN (...)` queries.
//

import Foundation

public enum SQLiteIDList {

	/// Returns `"<column> IN (SELECT value FROM json_each(?))"` and its JSON-encoded parameter.
	public static func clause(column: String, strings: some Collection<String>) -> (sql: String, parameter: String)? {
		guard !strings.isEmpty,
		      let data = try? JSONSerialization.data(withJSONObject: Array(strings)),
		      let json = String(data: data, encoding: .utf8) else {
			return nil
		}
		return ("\(column) IN (SELECT value FROM json_each(?))", json)
	}

	/// Returns `"<column> IN (SELECT value FROM json_each(?))"` and its JSON-encoded parameter for 64-bit integers.
	public static func clause(column: String, integers: some Collection<Int64>) -> (sql: String, parameter: String)? {
		guard !integers.isEmpty,
		      let data = try? JSONSerialization.data(withJSONObject: Array(integers)),
		      let json = String(data: data, encoding: .utf8) else {
			return nil
		}
		return ("\(column) IN (SELECT value FROM json_each(?))", json)
	}
}
