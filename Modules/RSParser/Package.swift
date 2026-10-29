// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "RSParser",
	platforms: [.iOS(.v16)],
	products: [
		.library(
			name: "RSParser",
			type: .dynamic,
			targets: ["RSParser"])
	],
	dependencies: [
		.package(path: "../RSCore")
	],
	targets: [
		.target(
			name: "RSParser",
			dependencies: ["RSCore"],
			swiftSettings: [
				.swiftLanguageMode(.v6),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]),
		.testTarget(
			name: "RSParserTests",
			dependencies: ["RSParser"],
			resources: [.copy("Resources")],
			swiftSettings: [
				.swiftLanguageMode(.v6),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		)
	]
)
