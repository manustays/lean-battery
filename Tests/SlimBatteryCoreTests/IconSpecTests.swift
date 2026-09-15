import Testing
@testable import SlimBatteryCore

@Suite struct IconSpecTests {
	@Test func onBatteryShowsNumberWithForegroundFill() {
		let spec = IconSpec(state: BatteryState(percent: 57))
		#expect(spec.fill == .foreground)
		#expect(spec.glyph == .number(57))
		#expect(spec.fillFraction == 0.57)
		#expect(!spec.showsHotBadge)
		#expect(spec.numberFontSize == 7.8)
	}

	@Test(arguments: [(20, IconSpec.Fill.low), (21, IconSpec.Fill.foreground), (1, IconSpec.Fill.low)])
	func lowThreshold(percent: Int, expected: IconSpec.Fill) {
		#expect(IconSpec(state: BatteryState(percent: percent)).fill == expected)
	}

	@Test func chargingShowsPlugWithGreenFill() {
		let spec = IconSpec(state: BatteryState(percent: 12, isCharging: true, isPluggedIn: true))
		#expect(spec.fill == .charging)
		#expect(spec.glyph == .plug)
	}

	@Test func pluggedInNotChargingShowsPlugWithForegroundFill() {
		let spec = IconSpec(state: BatteryState(percent: 80, isPluggedIn: true))
		#expect(spec.fill == .foreground)
		#expect(spec.glyph == .plug)
	}

	@Test func lowPowerModeWinsOverChargingAndLow() {
		#expect(IconSpec(state: BatteryState(percent: 45, isCharging: true, isPluggedIn: true, isLowPowerMode: true)).fill == .lowPower)
		#expect(IconSpec(state: BatteryState(percent: 10, isLowPowerMode: true)).fill == .lowPower)
	}

	@Test func fullUsesSmallerFont() {
		#expect(IconSpec(state: BatteryState(percent: 100)).numberFontSize == 5.6)
	}

	@Test func hotShowsBadge() {
		#expect(IconSpec(state: BatteryState(percent: 57, isHot: true)).showsHotBadge)
	}
}
