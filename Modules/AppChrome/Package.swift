// swift-tools-version:6.2
import PackageDescription

let package = Package(name: "AppChrome", platforms: [.iOS(.v17)], products: [.library(name: "AppChrome", type: .dynamic, targets: ["AppChrome"])], dependencies: [.package(path: "../Articles")], targets: [
	.target(name: "AppChrome", dependencies: ["Articles"], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault"), .enableUpcomingFeature("InferIsolatedConformances")]),
	.testTarget(name: "AppChromeTests", dependencies: ["AppChrome", "Articles"])
])
