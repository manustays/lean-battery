import Testing
@testable import LeanBatteryCore

@Suite struct PillContentTests {
	/// Builds an event with the flags the content never reads, so each test states only what matters.
	private func event(_ kind: NotificationEvent.Kind, _ state: BatteryState) -> NotificationEvent {
		NotificationEvent(kind: kind, state: state, showsGlow: false, playsSound: false)
	}

	@Test func belowRuleShowsPercentAndTimeLeft() {
		let content = PillContent(
			event: event(.below(threshold: 20), BatteryState(percent: 10, minutesRemaining: 38)),
			adapterWatts: nil)
		#expect(content.title == "Low Battery")
		#expect(content.detail == "10% · about 38m left")
	}

	@Test func belowRuleWithoutTimeShowsPercentOnly() {
		let content = PillContent(event: event(.below(threshold: 20), BatteryState(percent: 10)), adapterWatts: nil)
		#expect(content.detail == "10%")
	}

	@Test func belowRuleOverAnHourUsesHoursAndMinutes() {
		let content = PillContent(
			event: event(.below(threshold: 50), BatteryState(percent: 45, minutesRemaining: 245)),
			adapterWatts: nil)
		#expect(content.detail == "45% · about 4h 05m left")
	}

	@Test func aboveRuleNamesTheThresholdAndAdapter() {
		let content = PillContent(
			event: event(.above(threshold: 80), BatteryState(percent: 80, isPluggedIn: true)),
			adapterWatts: 96)
		#expect(content.title == "Charged to 80%")
		#expect(content.detail == "Power Adapter · 96 W")
	}

	@Test func aboveRuleWithUnknownWattsSaysPluggedIn() {
		let content = PillContent(
			event: event(.above(threshold: 80), BatteryState(percent: 80, isPluggedIn: true)),
			adapterWatts: nil)
		#expect(content.detail == "Plugged In")
	}

	@Test func connectedWhileChargingShowsAdapterAndTimeToFull() {
		let content = PillContent(
			event: event(.powerChange, BatteryState(percent: 57, isCharging: true, isPluggedIn: true, minutesRemaining: 70)),
			adapterWatts: 96)
		#expect(content.title == "Charging · 57%")
		#expect(content.detail == "Power Adapter · 96 W · 1h 10m to full")
	}

	@Test func connectedWhileChargingWithoutTimeOmitsTheTail() {
		let content = PillContent(
			event: event(.powerChange, BatteryState(percent: 57, isCharging: true, isPluggedIn: true)),
			adapterWatts: nil)
		#expect(content.detail == "Power Adapter")
	}

	@Test func connectedWithoutChargingShowsPercentOnly() {
		let content = PillContent(
			event: event(.powerChange, BatteryState(percent: 80, isPluggedIn: true)),
			adapterWatts: 96)
		#expect(content.title == "Plugged In · Not Charging")
		#expect(content.detail == "80%")
	}

	@Test func disconnectedShowsTimeLeft() {
		let content = PillContent(
			event: event(.powerChange, BatteryState(percent: 57, minutesRemaining: 245)),
			adapterWatts: nil)
		#expect(content.title == "On Battery · 57%")
		#expect(content.detail == "About 4h 05m left")
	}

	@Test func disconnectedWithoutTimeSaysCalculating() {
		let content = PillContent(event: event(.powerChange, BatteryState(percent: 57)), adapterWatts: nil)
		#expect(content.detail == "Calculating time left…")
	}
}
