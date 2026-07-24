//
//  AccountType+Helpers.swift
//  NetNewsWire
//
//  Created by Stuart Breckenridge on 27/10/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import Foundation
import Account
import UIKit
import SwiftUI

extension AccountType {

	// MARK: - Log Colors

	var logColor: Color {
		switch self {
		case .onMyMac:
			return .secondary
		}
	}

	// MARK: - SwiftUI Images
	@MainActor func image() -> Image {
		switch self {
		case .onMyMac:
			if UIDevice.current.userInterfaceIdiom == .pad {
				return Image("accountLocalPad")
			} else {
				return Image("accountLocalPhone")
			}
		}
	}

}
