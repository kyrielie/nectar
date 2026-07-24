//
//  RSImage-Extensions.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 4/11/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import RSCore
import Images
import UIKit

extension RSImage {

	static var appIconImage: RSImage? {
		// https://stackoverflow.com/a/51241158/14256
		if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
			let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
			let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
			let lastIcon = iconFiles.last {
			return RSImage(named: lastIcon)
		}
		return nil
	}
}

extension IconImage {
	static let appIcon: IconImage? = {
		if let image = RSImage.appIconImage {
			return IconImage(image)
		}
		return nil
	}()

	static let nnwFeedIcon = IconImage(Assets.Images.nnwFeedIcon)
}
