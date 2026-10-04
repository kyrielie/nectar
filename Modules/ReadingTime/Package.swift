// swift-tools-version:6.2
import PackageDescription

let package = Package(name: "ReadingTime", platforms: [.iOS(.v17)], products: [.library(name: "ReadingTime", type: .dynamic, targets: ["ReadingTime"])], targets: [
	.target(name: "ReadingTime", swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault"), .enableUpcomingFeature("InferIsolatedConformances")]),
	.testTarget(name: "ReadingTimeTests", dependencies: ["ReadingTime"])
])
