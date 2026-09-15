// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "SlimBattery",
	platforms: [.macOS(.v26)],
	targets: [
		.target(name: "SlimBatteryCore"),
		.testTarget(name: "SlimBatteryCoreTests", dependencies: ["SlimBatteryCore"]),
	]
)
