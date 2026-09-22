// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "HexColor",
	platforms: [.iOS(.v17)],
	products: [
		.library(
			name: "HexColor",
			type: .dynamic,
			targets: ["HexColor"])
	],
	targets: [
		.target(
			name: "HexColor",
			dependencies: [],
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]),
		.testTarget(
			name: "HexColorTests",
			dependencies: ["HexColor"])
	]
)
