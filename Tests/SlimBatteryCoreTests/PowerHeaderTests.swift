import Testing
@testable import SlimBatteryCore

/// AppleSmartBattery-like properties with a system load and optional adapter wattage.
private func registry(systemLoad: Int? = 15563, watts: Int? = nil) -> [String: Any] {
	var properties: [String: Any] = [:]
	if let systemLoad { properties["PowerTelemetryData"] = ["SystemLoad": systemLoad] }
	if let watts { properties["AdapterDetails"] = ["Watts": watts, "FamilyCode": 0] }
	return properties
}

@Suite struct PowerHeaderTests {
	@Test func onBattery() {
		let header = PowerHeader(state: BatteryState(percent: 83, minutesRemaining: 758, temperatureCelsius: 30.7), registry: registry())
		#expect(header.percentText == "83%")
		#expect(header.statusLine == "On Battery · 12h 38m left")
		#expect(header.sourceText == "Battery")
		#expect(header.drawText == "15.6 W")
		#expect(header.temperatureText == "30.7 °C")
		#expect(header.lowPowerModeText == "Automatic")
		#expect(header.fill == .foreground)
		#expect(header.fillFraction == 0.83)
	}

	@Test func chargingWithAdapterWattage() {
		let header = PowerHeader(state: BatteryState(percent: 57, isCharging: true, isPluggedIn: true, minutesRemaining: 42), registry: registry(watts: 96))
		#expect(header.statusLine == "Charging · 0h 42m to full")
		#expect(header.sourceText == "Adapter · 96 W")
		#expect(header.fill == .charging)
	}

	@Test func pluggedInNotChargingWithoutWattage() {
		let header = PowerHeader(state: BatteryState(percent: 80, isPluggedIn: true), registry: registry())
		#expect(header.statusLine == "Plugged In · Not Charging")
		#expect(header.sourceText == "Adapter")
	}

	@Test func calculatingWhenMinutesUnknown() {
		#expect(PowerHeader(state: BatteryState(percent: 50), registry: registry()).statusLine == "Calculating…")
	}

	@Test func missingValuesShowDash() {
		let header = PowerHeader(state: BatteryState(percent: 50), registry: [:])
		#expect(header.drawText == "—")
		#expect(header.temperatureText == "—")
	}

	@Test func lowPowerAndHot() {
		let header = PowerHeader(state: BatteryState(percent: 50, isLowPowerMode: true, temperatureCelsius: 41, isHot: true), registry: registry())
		#expect(header.lowPowerModeText == "Low Power")
		#expect(header.isLowPowerMode)
		#expect(header.isHot)
		#expect(header.fill == .lowPower)
	}

	@Test(arguments: [(0, "0h 00m"), (65, "1h 05m"), (245, "4h 05m")])
	func durationFormatting(minutes: Int, expected: String) {
		#expect(PowerHeader.duration(minutes: minutes) == expected)
	}
}
