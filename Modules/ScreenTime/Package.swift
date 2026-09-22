// swift-tools-version:6.2
import PackageDescription

let package = Package(name: "ScreenTime", platforms: [.iOS(.v17)], products: [.library(name: "ScreenTime", type: .dynamic, targets: ["ScreenTime"])], targets: [
	.target(name: "ScreenTime", swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault"), .enableUpcomingFeature("InferIsolatedConformances")]),
	.testTarget(name: "ScreenTimeTests", dependencies: ["ScreenTime"])
])
