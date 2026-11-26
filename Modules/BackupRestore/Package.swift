// swift-tools-version:6.2
import PackageDescription

let package = Package(name: "BackupRestore", platforms: [.iOS(.v16)], products: [.library(name: "BackupRestore", type: .dynamic, targets: ["BackupRestore"])], dependencies: [
	.package(path: "../Account"), .package(path: "../ArticleTheming"), .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20")
], targets: [
	.target(name: "BackupRestore", dependencies: ["Account", "ArticleTheming", "ZIPFoundation"], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault"), .enableUpcomingFeature("InferIsolatedConformances")]),
	.testTarget(name: "BackupRestoreTests", dependencies: ["BackupRestore", "Account", "ZIPFoundation"])
])
