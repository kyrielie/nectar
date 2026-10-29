//
//  ViewAvailability.swift
//  NetNewsWire-iOS
//
//  SwiftUI modifiers newer than the iOS 16.0 deployment target, wrapped so
//  call sites stay free of `#available`. Each helper is a no-op on the
//  older OS. Add new ones here and list them in `docs/upstream-drift.md`.
//

import SwiftUI

extension View {

	/// `scrollClipDisabled()` where available (iOS 17+). On iOS 16 the scroll
	/// view keeps clipping at its bounds, so content that overhangs the edge
	/// (shadows, selection rings) is cut off there.
	@ViewBuilder
	func scrollClipDisabledIfAvailable() -> some View {
		if #available(iOS 17, *) {
			self.scrollClipDisabled()
		} else {
			self
		}
	}
}
