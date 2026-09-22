// swift-tools-version:6.2
import PackageDescription

let package = Package(name: "BackupRestore", platforms: [.iOS(.v17)], products: [.library(name: "BackupRestore", type: .dynamic, targets: ["BackupRestore"])], dependencies: [
	.package(path: "../Account"), .package(path: "../ArticleTheming"), .package(url: "https://github.com/marmelroy/Zip.git", revision: "059e7346082d02de16220cd79df7db18ddeba8c3")
], targets: [
	.target(name: "BackupRestore", dependencies: ["Account", "ArticleTheming", "Zip"]),
	.testTarget(name: "BackupRestoreTests", dependencies: ["BackupRestore", "Account", "Zip"])
])
