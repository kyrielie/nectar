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
		.package(url: "https://github.com/marmelroy/Zip.git", revision: "bca30f6d6c7d37cbc4aa8f6b0002e281dcc36195")
	],
	targets: [
		.target(
			name: "ArticleTheming",
			dependencies: [
				"RSCore",
				"HexColor",
				"AppChrome",
				"Zip"
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
