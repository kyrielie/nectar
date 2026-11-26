// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "ArticleTheming",
	platforms: [.iOS(.v16)],
	products: [
		.library(
			name: "ArticleTheming",
			type: .dynamic,
			targets: ["ArticleTheming"])
	],
	dependencies: [
		.package(path: "../RSCore"),
		.package(path: "../HexColor"),
		.package(path: "../AppChrome"),
		.package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20")
	],
	targets: [
		.target(
			name: "ArticleTheming",
			dependencies: [
				"RSCore",
				"HexColor",
				"AppChrome",
				"ZIPFoundation"
			],
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]),
		.testTarget(
			name: "ArticleThemingTests",
			dependencies: ["ArticleTheming"])
	]
)
