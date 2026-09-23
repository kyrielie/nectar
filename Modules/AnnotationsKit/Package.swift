// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "AnnotationsKit",
	platforms: [.iOS(.v17)],
	products: [
		.library(name: "AnnotationsKit", type: .dynamic, targets: ["AnnotationsKit"])
	],
	dependencies: [
		.package(path: "../Articles")
	],
	targets: [
		.target(name: "AnnotationsKit", dependencies: ["Articles"]),
		.testTarget(name: "AnnotationsKitTests", dependencies: ["AnnotationsKit"])
	]
)
