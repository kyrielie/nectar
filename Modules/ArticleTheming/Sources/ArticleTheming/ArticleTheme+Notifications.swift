//
//  ArticleTheme+Notifications.swift
//  ArticleTheme+Notifications
//
//  Created by Stuart Breckenridge on 20/09/2021.
//  Copyright © 2021 Ranchero Software. All rights reserved.
//

import Foundation

public extension Notification.Name {
	static let didBeginDownloadingTheme = Notification.Name("didBeginDownloadingTheme")
	static let didEndDownloadingTheme = Notification.Name("didEndDownloadingTheme")
	static let didFailToImportThemeWithError = Notification.Name("didFailToImportThemeWithError")
}
