// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "AO3Kit",
	platforms: [.iOS(.v17)],
	products: [
		.library(name: "AO3Kit", type: .dynamic, targets: ["AO3Kit"])
	],
	dependencies: [
		.package(path: "../RSParser"),
		.package(path: "../RSWeb"),
		.package(path: "../RSCore"),
		.package(path: "../ActivityLog"),
		.package(path: "../Articles"),
		.package(path: "../ArticlesDatabase")
	],
	targets: [
		.target(
			name: "AO3Kit",
			dependencies: ["RSParser", "RSWeb", "RSCore", "ActivityLog", "Articles", "ArticlesDatabase"],
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]),
		.testTarget(
			name: "AO3KitTests",
			dependencies: ["AO3Kit", "Articles", "ArticlesDatabase", "RSParser"],
			resources: [.copy("Resources")],
			swiftSettings: [.swiftLanguageMode(.v6)])
	]
)
