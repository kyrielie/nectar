// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "ArticleTheming",
	platforms: [.iOS(.v17)],
	products: [
		.library(
			name: "ArticleTheming",
			type: .dynamic,
			targets: ["ArticleTheming"])
	],
	dependencies: [
		.package(path: "../RSCore"),
		.package(path: "../HexColor"),
		.package(url: "https://github.com/marmelroy/Zip.git", revision: "059e7346082d02de16220cd79df7db18ddeba8c3")
	],
	targets: [
		.target(
			name: "ArticleTheming",
			dependencies: [
				"RSCore",
				"HexColor",
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
