//
//  ArticleThemeColorMeasurement.swift
//  ArticleTheming
//
//  The result of rendering a theme and reading back its painted colors, in
//  light and dark. Produced by `ArticleThemeColorProbe`, persisted by the
//  color store. All colors are opaque sRGB `#RRGGBB`.
//

import Foundation

public struct ArticleThemeColorMeasurement: Codable, Sendable, Equatable {
	public var pageLight: String
	public var pageDark: String
	public var inkLight: String
	public var inkDark: String
	public var linkLight: String
	public var linkDark: String
	public var pageWasPaintedLight: Bool
	public var pageWasPaintedDark: Bool
	/// True when any of page, ink or link differs between light and dark.
	/// Derived at measurement time and stored so the bundled table carries it.
	public var hasDarkModeVariant: Bool

	public init(pageLight: String, pageDark: String,
				inkLight: String, inkDark: String,
				linkLight: String, linkDark: String,
				pageWasPaintedLight: Bool, pageWasPaintedDark: Bool,
				hasDarkModeVariant: Bool) {
		self.pageLight = pageLight
		self.pageDark = pageDark
		self.inkLight = inkLight
		self.inkDark = inkDark
		self.linkLight = linkLight
		self.linkDark = linkDark
		self.pageWasPaintedLight = pageWasPaintedLight
		self.pageWasPaintedDark = pageWasPaintedDark
		self.hasDarkModeVariant = hasDarkModeVariant
	}
}
