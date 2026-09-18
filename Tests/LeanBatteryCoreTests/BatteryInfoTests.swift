import Testing
import Foundation
@testable import LeanBatteryCore

@Suite struct BatteryInfoTests {
	@Test func fullData() {
		let info = BatteryInfo(
			powerSource: ["BatteryHealth": "Good"],
			registry: ["AppleRawMaxCapacity": 5480, "DesignCapacity": 6249, "CycleCount": 437, "Voltage": 12178, "AdapterDetails": ["Watts": 96]]
		)
		#expect(info.rows == [
			.init(label: "Health", value: "88%"),
			.init(label: "Condition", value: "Good"),
			.init(label: "Cycle count", value: "437"),
			.init(label: "Capacity", value: "5480 / 6249 mAh"),
			.init(label: "Voltage", value: "12.18 V"),
			.init(label: "Adapter", value: "96 W"),
		])
	}

	@Test func bridgesNSNumberBackedRegistryValues() {
		let info = BatteryInfo(
			powerSource: ["BatteryHealth": "Good"],
			registry: [
				"AppleRawMaxCapacity": NSNumber(value: 5480),
				"DesignCapacity": NSNumber(value: 6249),
				"CycleCount": NSNumber(value: 437),
				"Voltage": NSNumber(value: 12178),
				"AdapterDetails": ["Watts": NSNumber(value: 96)] as NSDictionary,
			]
		)
		#expect(info.rows == [
			.init(label: "Health", value: "88%"),
			.init(label: "Condition", value: "Good"),
			.init(label: "Cycle count", value: "437"),
			.init(label: "Capacity", value: "5480 / 6249 mAh"),
			.init(label: "Voltage", value: "12.18 V"),
			.init(label: "Adapter", value: "96 W"),
		])
	}

	@Test func missingDataShowsDash() {
		let info = BatteryInfo(powerSource: ["BatteryHealth": ""], registry: ["DesignCapacity": 0, "AppleRawMaxCapacity": 5480, "AdapterDetails": ["FamilyCode": 0]])
		#expect(info.rows.allSatisfy { $0.value == "—" })
	}
}
