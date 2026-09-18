// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "LeanBattery",
	platforms: [.macOS(.v26)],
	targets: [
		.target(name: "LeanBatteryCore"),
		.executableTarget(name: "LeanBattery", dependencies: ["LeanBatteryCore"]),
		.testTarget(name: "LeanBatteryCoreTests", dependencies: ["LeanBatteryCore"]),
	]
)
