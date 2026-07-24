//
//  AddCloudKitAccount.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/22/25.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import Foundation
import UIKit
import RSCore

enum AddCloudKitAccountError: LocalizedError, RecoverableError, Sendable {
	case iCloudDriveMissing

	var errorDescription: String? {
		NSLocalizedString("Can’t Add iCloud Account", comment: "CloudKit account setup failure description — iCloud Drive not enabled.")
	}

	var recoverySuggestion: String? {
		NSLocalizedString("Open Settings to configure iCloud and enable iCloud Drive.", comment: "CloudKit account setup recovery suggestion")
	}

	var recoveryOptions: [String] {
		[NSLocalizedString("Open Settings", comment: "Open Settings button"), NSLocalizedString("Cancel", comment: "Cancel button")]
	}

	func attemptRecovery(optionIndex recoveryOptionIndex: Int) -> Bool {
		guard recoveryOptionIndex == 0 else {
			return false
		}

		Task { @MainActor in
			AddCloudKitAccountUtilities.openiCloudSettings()
		}

		return true
	}
}

struct AddCloudKitAccountUtilities {
	static var isiCloudDriveEnabled: Bool {
		Platform.deviceHasiCloudAccount
	}

	@MainActor static func openiCloudSettings() {
		if let url = URL(string: "App-prefs:APPLE_ACCOUNT") {
			UIApplication.shared.open(url)
		}
	}
}
