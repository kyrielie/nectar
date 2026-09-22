// swift-tools-version:6.2
import PackageDescription

let package = Package(name: "ReadingStats", platforms: [.iOS(.v17)], products: [.library(name: "ReadingStats", type: .dynamic, targets: ["ReadingStats"])], targets: [
	.target(name: "ReadingStats", swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault"), .enableUpcomingFeature("InferIsolatedConformances")]),
	.testTarget(name: "ReadingStatsTests", dependencies: ["ReadingStats"])
])
