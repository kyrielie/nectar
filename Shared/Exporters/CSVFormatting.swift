//
//  CSVFormatting.swift
//  NetNewsWire
//
//  Field-escaping and row-joining rules shared by every CSV exporter in
//  this codebase. Pulled out of ArticleCSVExporter (whose escapedCSVField/
//  rowString were private static, and so couldn't be called from a second
//  exporter as-is) rather than letting AnnotationCSVExporter hand-roll its
//  own copy of the same escaping logic. ArticleCSVExporterTests already
//  covers these rules directly.
//

import Foundation

@MainActor enum CSVFormatting {

	static func rowString(for columns: [String]) -> String {
		return columns.map(escapedField).joined(separator: ",")
	}

	static func escapedField(_ field: String) -> String {
		guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
			return field
		}
		return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
	}
}
