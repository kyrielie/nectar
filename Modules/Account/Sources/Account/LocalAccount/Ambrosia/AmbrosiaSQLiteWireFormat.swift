//
//  AmbrosiaSQLiteWireFormat.swift
//  NetNewsWire
//
//  Nectar Implementation Plan, Wire Contract > Versioning.
//
//  This integer must stay identical to the matching constant hardcoded in
//  the Ambrosia codebase (which stamps it via `PRAGMA user_version` when it
//  writes a `.sqlite` transfer file). On any mismatch between a downloaded
//  file's `PRAGMA user_version` and this constant: hard failure, surfaced as
//  a clear user-facing error. No fallback to the JSON route, no partial-
//  compatibility handling -- a mismatch means a build/version skew bug.
//
enum AmbrosiaSQLiteWireFormat {
	static let version: Int32 = 1
}
