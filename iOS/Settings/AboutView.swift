//
//  AboutView.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 15/09/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
		ScrollView(.vertical) {
			VStack(alignment: .center, spacing: 12) {
				Image("nnwFeedIcon")
					.resizable()
					.frame(width: 100, height: 100)
					.clipShape(RoundedRectangle(cornerRadius: 20))

				Text(verbatim: "NetNewsWire")
					.font(.largeTitle)

				Text(verbatim: "By Brent Simmons and the Ranchero Software team")
					.foregroundStyle(.secondary)
				Text("[netnewswire.com](https://netnewswire.com/)")

				VStack(spacing: 6) {
					Text(verbatim: "Nectar")
						.bold()
						.foregroundStyle(.secondary)
						.padding(.top, 16)
					Text(verbatim: "Nectar is a private fork of NetNewsWire for reading Ambrosia JSON feeds.")
				}

				VStack(spacing: 6) {
					Text(verbatim: "Credits")
						.bold()
						.foregroundStyle(.secondary)
						.padding(.top, 16)
					AboutCreditView(contributorType: "Contributing Developers", contributors: [.mauriceParker, .stuartBreckenridge])
					AboutCreditView(contributorType: "App Icon", contributors: [.bradEllis])
					AboutCreditView(contributorType: "Under-the-hood magic & CSS", contributors: [.nateWeaver])
					AboutCreditView(contributorType: "Newsfoot (JS footnote displayer)", contributors: [.andrewBrehaut])
					AboutCreditView(contributorType: "Help Book", contributors: [.ryanDotson])
					AboutCreditView(contributorType: "Featuring additional contributions from", contributors: [.danielJalkut, .joeHeck, .olofHellman, .rizwanMohamedIbrahim, .philViso, .others])
				}

				VStack(spacing: 6) {
					Text(verbatim: "Open Source")
						.bold()
						.foregroundStyle(.secondary)
						.padding(.top, 16)
					Text("Nectar is a fork of [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire) (MIT) and is the companion app for [Ambrosia](https://github.com/kyrielie/ambrosia) (MIT). Thanks also to the [Organization for Transformative Works](https://github.com/otwcode/otwarchive) (GPL-2.0-or-later), nianeyna's [ao3downloader](https://github.com/nianeyna/ao3downloader) (GPL-3.0), and ArmindoFlores's [ao3_api](https://github.com/ArmindoFlores/ao3_api) (MIT), for AO3 parsing reference. Several bundled article themes are inspired by community AO3 workskins, including work by [ZerafinaCSS](https://github.com/ZerafinaCSS/neos), the [Dracula Theme](https://github.com/dracula/archive-of-our-own) project, and [BlackBatCat](https://github.com/Wolfbatcat/ao3-rose-pine), among others. Full attribution for every theme and third-party code reference is in [`THIRD-PARTY-NOTICES.md`](https://github.com/kyrielie/nectar/blob/main/THIRD-PARTY-NOTICES.md) in the source repository. Broadsheet theme from [here](https://github.com/stuartbreckenridge/NNWThemesBroadsheet).")
				}

				VStack(spacing: 6) {
					Text(verbatim: "Thanks")
						.bold()
						.foregroundStyle(.secondary)
						.padding(.top, 16)
					Text("Thanks to Sheila and my family; thanks to my friends in Seattle and around the globe; thanks to the ever-patient and ever-awesome NetNewsWire beta testers.\n\nThanks to [Gus Mueller](https://shapeof.com/) for [FMDB](https://github.com/ccgus/fmdb) by [Flying Meat Software](http://flyingmeat.com/). Thanks to [GitHub](https://github.com) and [Discourse](https://discourse.com) for making open source collaboration easy and fun. Thanks to [Ben Ubois](https://benubois.com/) at [Feedbin](https://feedbin.com) for all the extra help with syncing and article rendering — and [for hosting the server for the Reader view](https://feedbin.com/blog/2019/03/11/the-future-of-full-content/).")
				}

				VStack(spacing: 6) {
					Text(verbatim: "Dedication")
						.bold()
						.foregroundStyle(.secondary)
						.padding(.top, 16)
					Text("NetNewsWire 7 is dedicated to everyone working to save democracy in the United States and around the world.")
				}

				Text(verbatim: "Copyright © 2002-2026 Brent Simmons")
					.font(.caption)
					.foregroundStyle(.secondary)
					.padding(.bottom)
			}
			.scenePadding(.horizontal)
		}
		.multilineTextAlignment(.center)
		.navigationTitle(Text(verbatim: "About Nectar"))
    }
}

#Preview {
    AboutView()
}
