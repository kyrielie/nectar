//
//  TimelineCustomizerView.swift
//  NetNewsWire-iOS
//
//  SwiftUI replacement for `TimelineCustomizerCollectionViewController`:
//  Stepper for Number of Lines, segmented Picker for Tag Display, Toggle for
//  Show Stats, and live `MainTimelineCell` preview.
//

import SwiftUI
import UIKit
import Articles
import AppChrome
import Images

@MainActor final class TimelineCustomizerModel: ObservableObject {

	static var previewArticle: Article {
		var components = DateComponents()
		components.year = 1954
		components.month = 7
		components.day = 29

		let calendar = Calendar.current
		let date = calendar.date(from: components)!

		return Article(
			accountID: "_testID",
			articleID: "_testArticleID",
			feedID: "_testFeedID",
			uniqueID: UUID().uuidString,
			title: "At The Sign Of The Prancing Pony",
			contentHTML: nil,
			contentText: "Bree was the chief village of Bree-land, a small country a few miles broad whose chief claim to fame was its aluminum siding industry. The Men of Bree were cheerful and independent: they belonged to nobody but themselves. In the lands beyond Bree there were mysterious wanderers.",
			markdown: nil,
			url: nil,
			externalURL: nil,
			summary: nil,
			imageURL: nil,
			datePublished: date,
			dateModified: nil,
			authors: Set([Author(authorID: "_testAuthorID", name: "J. R. R. Tolkien", url: nil, avatarURL: nil, emailAddress: nil)!]),
			wordCount: 4231,
			isComplete: false,
			fandoms: ["The Lord of the Rings - J. R. R. Tolkien"],
			relationships: ["Aragorn/Arwen"],
			characters: ["Aragorn", "Frodo Baggins", "Barliman Butterbur"],
			ratings: ["Teen And Up Audiences"],
			warnings: ["No Archive Warnings Apply"],
			categories: ["Fluff", "Canon-Compliant", "Introspection"],
			status: ArticleStatus(articleID: "_testArticleID", read: false, starred: false, dateArrived: .now)
		)
	}

	@Published var numberOfLines: Int {
		didSet {
			guard oldValue != numberOfLines else { return }
			AppDefaults.shared.timelineNumberOfLines = numberOfLines
		}
	}

	@Published var tagDisplayMode: TagDisplayMode {
		didSet {
			guard oldValue != tagDisplayMode else { return }
			AppDefaults.shared.timelineTagDisplayMode = tagDisplayMode
		}
	}

	@Published var statsVisible: Bool {
		didSet {
			guard oldValue != statsVisible else { return }
			AppDefaults.shared.statsVisible = statsVisible
		}
	}

	init() {
		self.numberOfLines = AppDefaults.shared.timelineNumberOfLines
		self.tagDisplayMode = AppDefaults.shared.timelineTagDisplayMode
		self.statsVisible = AppDefaults.shared.statsVisible
	}
}

struct TimelineCustomizerView: View {

	@StateObject private var model = TimelineCustomizerModel()

	var body: some View {

		Form {
			Section {
				Stepper(value: $model.numberOfLines, in: 1...6) {
					LabeledContent(
						NSLocalizedString("Title & Summary Lines", comment: "Timeline layout: number of lines"),
						value: "\(model.numberOfLines)"
					)
				}
			} footer: {
				Text("Maximum combined lines for the work title and summary. Longer titles leave fewer lines for the summary.", comment: "Timeline layout: number of lines footer")
			}
			.surfacePaletteRowBackground()

			Section {
				Picker(NSLocalizedString("Tag Display", comment: "Timeline layout: tag display"), selection: $model.tagDisplayMode) {
					Text(TagDisplayMode.compact.description).tag(TagDisplayMode.compact)
					Text(TagDisplayMode.expanded.description).tag(TagDisplayMode.expanded)
					Text(TagDisplayMode.badges.description).tag(TagDisplayMode.badges)
				}
				.pickerStyle(.segmented)
				.labelsHidden()
			} header: {
				Text("Tag Display", comment: "Timeline layout: tag display section header")
			}
			.surfacePaletteRowBackground()

			Section {
				Toggle(NSLocalizedString("Show Stats", comment: "Stats visibility toggle"), isOn: $model.statsVisible)
			} footer: {
				Text("Shows word count, completion status, and work tags in the timeline.", comment: "Timeline layout: show stats footer")
			}
			.surfacePaletteRowBackground()

			Section {
				TimelinePreviewRepresentable(
					numberOfLines: model.numberOfLines,
					tagDisplayMode: model.tagDisplayMode,
					statsVisible: model.statsVisible
				)
				.listRowInsets(EdgeInsets())
			} header: {
				Text("Preview", comment: "Timeline layout: preview section header")
			}
			.surfacePaletteRowBackground()
		}
		.surfacePaletteListBackground()
		.navigationTitle(Text("Timeline Layout", comment: "Timeline Layout"))
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct TimelinePreviewRepresentable: UIViewRepresentable {
	let numberOfLines: Int
	let tagDisplayMode: TagDisplayMode
	let statsVisible: Bool

	func makeUIView(context: Context) -> TimelinePreviewContainerView {
		let containerView = TimelinePreviewContainerView()
		containerView.update(numberOfLines: numberOfLines, tagDisplayMode: tagDisplayMode, statsVisible: statsVisible)
		return containerView
	}

	func updateUIView(_ containerView: TimelinePreviewContainerView, context: Context) {
		containerView.update(numberOfLines: numberOfLines, tagDisplayMode: tagDisplayMode, statsVisible: statsVisible)
	}

	func sizeThatFits(_ proposal: ProposedViewSize, uiView containerView: TimelinePreviewContainerView, context: Context) -> CGSize? {
		let width = proposal.width ?? 320
		let height = containerView.preferredHeight(forWidth: width)
		return CGSize(width: width, height: height)
	}
}

final class TimelinePreviewContainerView: UIView {

	private let cell = MainTimelineCell(frame: .zero)
	private var lastNumberOfLines: Int?
	private var lastTagDisplayMode: TagDisplayMode?
	private var lastStatsVisible: Bool?
	private var lastAccentColor: AccentColor?
	private var lastBadgeColorMode: BadgeColorPalette?

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = .clear
		cell.isPreview = true
		addSubview(cell)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		cell.frame = bounds
		cell.layoutIfNeeded()
	}

	func update(
		numberOfLines: Int,
		tagDisplayMode: TagDisplayMode,
		statsVisible: Bool,
		accentColor: AccentColor = AppDefaults.shared.accentColor,
		badgeColorMode: BadgeColorPalette = AppDefaults.shared.badgeColorMode
	) {
		guard lastNumberOfLines != numberOfLines
			|| lastTagDisplayMode != tagDisplayMode
			|| lastStatsVisible != statsVisible
			|| lastAccentColor != accentColor
			|| lastBadgeColorMode != badgeColorMode else {
			return
		}
		lastNumberOfLines = numberOfLines
		lastTagDisplayMode = tagDisplayMode
		lastStatsVisible = statsVisible
		lastAccentColor = accentColor
		lastBadgeColorMode = badgeColorMode

		cell.cellData = MainTimelineCellData(
			article: TimelineCustomizerModel.previewArticle,
			showFeedName: .byline,
			feedName: "The Fellowship of the Ring",
			byline: "J. R. R. Tolkien",
			iconImage: IconImage(Assets.Images.nnwFeedIcon),
			showIcon: false,
			numberOfLines: numberOfLines,
			iconSize: AppDefaults.shared.timelineIconSize,
			tagDisplayMode: tagDisplayMode
		)
		cell.updateConfiguration(using: UICellConfigurationState(traitCollection: traitCollection))
		cell.setNeedsLayout()
		cell.layoutIfNeeded()
		setNeedsLayout()
		invalidateIntrinsicContentSize()
	}

	func preferredHeight(forWidth width: CGFloat) -> CGFloat {
		let targetWidth = max(width, 1)
		let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
		attributes.frame = CGRect(x: 0, y: 0, width: targetWidth, height: 1000)
		return max(cell.preferredLayoutAttributesFitting(attributes).frame.height, 44)
	}
}
