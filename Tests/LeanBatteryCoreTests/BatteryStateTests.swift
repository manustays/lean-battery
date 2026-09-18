import Testing
@testable import LeanBatteryCore

/// Builds an IOPS-like power source description.
private func powerSource(
	capacity: Int = 57,
	state: String = "Battery Power",
	charging: Bool = false,
	toEmpty: Int = 245,
	toFull: Int = 0
) -> [String: Any] {
	[
		"Current Capacity": capacity, "Max Capacity": 100, "Power Source State": state,
		"Is Charging": charging, "Time to Empty": toEmpty, "Time to Full Charge": toFull,
	]
}

@Suite struct BatteryStateTests {
	@Test func parsesOnBattery() throws {
		let state = try #require(BatteryState.make(powerSource: powerSource(), registry: ["Temperature": 3081], isLowPowerMode: false, hotThresholdCelsius: 40))
		#expect(state == BatteryState(percent: 57, minutesRemaining: 245, temperatureCelsius: 30.81))
	}

	@Test func parsesCharging() throws {
		let state = try #require(BatteryState.make(powerSource: powerSource(capacity: 83, state: "AC Power", charging: true, toFull: 42), registry: [:], isLowPowerMode: false, hotThresholdCelsius: 40))
		#expect(state == BatteryState(percent: 83, isCharging: true, isPluggedIn: true, minutesRemaining: 42))
	}

	@Test func parsesPluggedInNotCharging() throws {
		let state = try #require(BatteryState.make(powerSource: powerSource(capacity: 80, state: "AC Power"), registry: [:], isLowPowerMode: true, hotThresholdCelsius: 40))
		#expect(state.isPluggedIn)
		#expect(!state.isCharging)
		#expect(state.isLowPowerMode)
	}

	@Test func calculatingTimeIsNil() throws {
		let state = try #require(BatteryState.make(powerSource: powerSource(toEmpty: -1), registry: [:], isLowPowerMode: false, hotThresholdCelsius: 40))
		#expect(state.minutesRemaining == nil)
	}

	@Test(arguments: [(3999, false), (4000, true), (4500, true)])
	func hotAtOrAboveThreshold(rawTemperature: Int, expectedHot: Bool) throws {
		let state = try #require(BatteryState.make(powerSource: powerSource(), registry: ["Temperature": rawTemperature], isLowPowerMode: false, hotThresholdCelsius: 40))
		#expect(state.isHot == expectedHot)
	}

	@Test func missingTemperatureIsNotHot() throws {
		let state = try #require(BatteryState.make(powerSource: powerSource(), registry: [:], isLowPowerMode: false, hotThresholdCelsius: 0))
		#expect(state.temperatureCelsius == nil)
		#expect(!state.isHot)
	}

	@Test func missingCapacityReturnsNil() {
		#expect(BatteryState.make(powerSource: [:], registry: [:], isLowPowerMode: false, hotThresholdCelsius: 40) == nil)
	}

	@Test func accessibilityDescriptionListsActiveStates() {
		#expect(BatteryState(percent: 57).accessibilityDescription == "Battery 57%")
		#expect(BatteryState(percent: 83, isCharging: true, isPluggedIn: true, isLowPowerMode: true, isHot: true).accessibilityDescription == "Battery 83%, charging, Low Power Mode, hot")
		#expect(BatteryState(percent: 80, isPluggedIn: true).accessibilityDescription == "Battery 80%, plugged in, not charging")
	}
}
