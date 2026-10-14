// swift-tools-version:6.2
import PackageDescription

let package = Package(name: "BackupRestore", platforms: [.iOS(.v17)], products: [.library(name: "BackupRestore", type: .dynamic, targets: ["BackupRestore"])], dependencies: [
	.package(path: "../Account"), .package(path: "../ArticleTheming"), .package(url: "https://github.com/marmelroy/Zip.git", revision: "bca30f6d6c7d37cbc4aa8f6b0002e281dcc36195")
], targets: [
	.target(name: "BackupRestore", dependencies: ["Account", "ArticleTheming", "Zip"], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault"), .enableUpcomingFeature("InferIsolatedConformances")]),
	.testTarget(name: "BackupRestoreTests", dependencies: ["BackupRestore", "Account", "Zip"])
])
