// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "Account",
	platforms: [.iOS(.v17)],
	products: [
		.library(
			name: "Account",
			type: .dynamic,
			targets: ["Account"])
	],
	dependencies: [
		.package(path: "../ActivityLog"),
		.package(path: "../Articles"),
		.package(path: "../ArticlesDatabase"),
		.package(path: "../FeedFinder"),
		.package(path: "../ErrorLog"),
		.package(path: "../SyncDatabase"),
		.package(path: "../RSWeb"),
		.package(path: "../RSParser"),
		.package(path: "../RSCore"),
		.package(path: "../RSDatabase")
	],
	targets: [
		.target(
			name: "Account",
			dependencies: [
				"RSCore",
				"RSDatabase",
				"RSParser",
				"RSWeb",
				"ActivityLog",
				"Articles",
				"ArticlesDatabase",
				"ErrorLog",
				"FeedFinder",
				"SyncDatabase"
			],
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		),
		.testTarget(
			name: "AccountTests",
			dependencies: ["Account", "RSParser"],
			resources: [
				.copy("Resources")
			],
			swiftSettings: [.swiftLanguageMode(.v6)]
		)
	]
)
