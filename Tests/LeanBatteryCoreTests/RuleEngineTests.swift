import Testing
@testable import LeanBatteryCore

@Suite struct RuleEngineTests {
	private let below20 = NotificationRule(direction: .below, threshold: 20, glow: true, sound: true)
	private let below10 = NotificationRule(direction: .below, threshold: 10)
	private let above80 = NotificationRule(direction: .above, threshold: 80, sound: true)

	/// Battery state on battery power at `percent`.
	private func onBattery(_ percent: Int) -> BatteryState {
		BatteryState(percent: percent)
	}

	/// Battery state with the adapter connected at `percent`.
	private func pluggedIn(_ percent: Int) -> BatteryState {
		BatteryState(percent: percent, isCharging: true, isPluggedIn: true)
	}

	/// Engine armed from `state` with `rules`.
	private func armed(_ rules: [NotificationRule], at state: BatteryState) -> RuleEngine {
		var engine = RuleEngine()
		engine.sync(rules: rules, state: state)
		return engine
	}

	@Test func belowRuleFiresOnceWhenCrossing() {
		var engine = armed([below20], at: onBattery(50))
		let first = engine.evaluate(
			previous: onBattery(21), current: onBattery(20), rules: [below20],
			powerChangeAlerts: false, powerChangeSound: false)
		#expect(first?.kind == .below(threshold: 20))
		#expect(first?.showsGlow == true)
		#expect(first?.playsSound == true)

		let second = engine.evaluate(
			previous: onBattery(20), current: onBattery(19), rules: [below20],
			powerChangeAlerts: false, powerChangeSound: false)
		#expect(second == nil)
	}

	@Test func belowRuleRearmsTwoPointsAboveTheThreshold() {
		var engine = armed([below20], at: onBattery(50))
		_ = engine.evaluate(previous: onBattery(21), current: onBattery(20), rules: [below20], powerChangeAlerts: false, powerChangeSound: false)
		// 21% is one point above: still disarmed.
		#expect(engine.evaluate(previous: onBattery(20), current: onBattery(21), rules: [below20], powerChangeAlerts: false, powerChangeSound: false) == nil)
		#expect(engine.evaluate(previous: onBattery(21), current: onBattery(19), rules: [below20], powerChangeAlerts: false, powerChangeSound: false) == nil)
		// 22% re-arms, so the next crossing fires again.
		#expect(engine.evaluate(previous: onBattery(19), current: onBattery(22), rules: [below20], powerChangeAlerts: false, powerChangeSound: false) == nil)
		#expect(engine.evaluate(previous: onBattery(22), current: onBattery(20), rules: [below20], powerChangeAlerts: false, powerChangeSound: false)?.kind == .below(threshold: 20))
	}

	@Test func pluggingInRearmsABelowRule() {
		var engine = armed([below20], at: onBattery(50))
		_ = engine.evaluate(previous: onBattery(21), current: onBattery(20), rules: [below20], powerChangeAlerts: false, powerChangeSound: false)
		// Plugged in at the same level: re-armed, but a below rule cannot fire on adapter power.
		#expect(engine.evaluate(previous: onBattery(20), current: pluggedIn(20), rules: [below20], powerChangeAlerts: false, powerChangeSound: false) == nil)
		// Unplugging while still at or under the threshold fires (spec §6.2 consequence).
		#expect(engine.evaluate(previous: pluggedIn(20), current: onBattery(20), rules: [below20], powerChangeAlerts: false, powerChangeSound: false)?.kind == .below(threshold: 20))
	}

	@Test func aboveRuleFiresWhileCharging() {
		var engine = armed([above80], at: pluggedIn(50))
		let event = engine.evaluate(previous: pluggedIn(79), current: pluggedIn(80), rules: [above80], powerChangeAlerts: false, powerChangeSound: false)
		#expect(event?.kind == .above(threshold: 80))
		#expect(event?.showsGlow == false)
		#expect(event?.playsSound == true)
	}

	@Test func pluggingInAboveTheThresholdStaysSilent() {
		var engine = armed([above80], at: onBattery(85))
		#expect(engine.evaluate(previous: onBattery(85), current: pluggedIn(85), rules: [above80], powerChangeAlerts: false, powerChangeSound: false) == nil)
	}

	@Test func aboveRuleRearmsOnlyTwoPointsBelowTheThreshold() {
		var engine = armed([above80], at: pluggedIn(50))
		_ = engine.evaluate(previous: pluggedIn(79), current: pluggedIn(80), rules: [above80], powerChangeAlerts: false, powerChangeSound: false)
		#expect(engine.evaluate(previous: pluggedIn(80), current: pluggedIn(79), rules: [above80], powerChangeAlerts: false, powerChangeSound: false) == nil)
		#expect(engine.evaluate(previous: pluggedIn(79), current: pluggedIn(81), rules: [above80], powerChangeAlerts: false, powerChangeSound: false) == nil)
		#expect(engine.evaluate(previous: pluggedIn(81), current: pluggedIn(78), rules: [above80], powerChangeAlerts: false, powerChangeSound: false) == nil)
		#expect(engine.evaluate(previous: pluggedIn(78), current: pluggedIn(80), rules: [above80], powerChangeAlerts: false, powerChangeSound: false)?.kind == .above(threshold: 80))
	}

	@Test func theFirstStateNeverFires() {
		var engine = RuleEngine()
		engine.sync(rules: [below20], state: nil)
		#expect(engine.evaluate(previous: nil, current: onBattery(5), rules: [below20], powerChangeAlerts: true, powerChangeSound: false) == nil)
	}

	@Test func aJumpPastSeveralBelowRulesPicksTheLowest() {
		var engine = armed([below20, below10], at: onBattery(50))
		let event = engine.evaluate(previous: onBattery(50), current: onBattery(8), rules: [below20, below10], powerChangeAlerts: false, powerChangeSound: false)
		#expect(event?.kind == .below(threshold: 10))
		// The suppressed 20% rule also disarmed, so it does not fire on the next step down.
		#expect(engine.evaluate(previous: onBattery(8), current: onBattery(7), rules: [below20, below10], powerChangeAlerts: false, powerChangeSound: false) == nil)
	}

	@Test func aJumpPastSeveralAboveRulesPicksTheHighest() {
		let above90 = NotificationRule(direction: .above, threshold: 90)
		var engine = armed([above80, above90], at: pluggedIn(50))
		let event = engine.evaluate(previous: pluggedIn(50), current: pluggedIn(95), rules: [above80, above90], powerChangeAlerts: false, powerChangeSound: false)
		#expect(event?.kind == .above(threshold: 90))
	}

	@Test func aRuleEventBeatsAPowerChangeEvent() {
		var engine = armed([below20], at: pluggedIn(15))
		let event = engine.evaluate(previous: pluggedIn(15), current: onBattery(15), rules: [below20], powerChangeAlerts: true, powerChangeSound: true)
		#expect(event?.kind == .below(threshold: 20))
	}

	@Test func powerChangeFiresOnlyWhenEnabled() {
		var engine = armed([], at: onBattery(57))
		#expect(engine.evaluate(previous: onBattery(57), current: pluggedIn(57), rules: [], powerChangeAlerts: false, powerChangeSound: false) == nil)
		let event = engine.evaluate(previous: onBattery(57), current: pluggedIn(57), rules: [], powerChangeAlerts: true, powerChangeSound: true)
		#expect(event?.kind == .powerChange)
		#expect(event?.playsSound == true)
		#expect(event?.showsGlow == false)
		// Same power source, only a level change: nothing.
		#expect(engine.evaluate(previous: pluggedIn(57), current: pluggedIn(58), rules: [], powerChangeAlerts: true, powerChangeSound: true) == nil)
	}

	@Test func disabledRulesAreIgnored() {
		var disabled = below20
		disabled.isEnabled = false
		var engine = armed([disabled], at: onBattery(50))
		#expect(engine.evaluate(previous: onBattery(21), current: onBattery(20), rules: [disabled], powerChangeAlerts: false, powerChangeSound: false) == nil)
	}

	@Test func anEditedRuleRearmsFromTheLevelAtEditTime() {
		var engine = armed([below20], at: onBattery(50))
		_ = engine.evaluate(previous: onBattery(21), current: onBattery(20), rules: [below20], powerChangeAlerts: false, powerChangeSound: false)
		// The user moves the threshold to 30 while sitting at 50%: armed again from there.
		var moved = below20
		moved.threshold = 30
		engine.sync(rules: [moved], state: onBattery(50))
		#expect(engine.evaluate(previous: onBattery(50), current: onBattery(29), rules: [moved], powerChangeAlerts: false, powerChangeSound: false)?.kind == .below(threshold: 30))
	}

	@Test func aRuleCreatedBelowItsThresholdDoesNotFireImmediately() {
		var engine = armed([below20], at: onBattery(15))
		#expect(engine.evaluate(previous: onBattery(15), current: onBattery(14), rules: [below20], powerChangeAlerts: false, powerChangeSound: false) == nil)
		// It arms again once the level climbs two points past the threshold.
		#expect(engine.evaluate(previous: onBattery(14), current: onBattery(22), rules: [below20], powerChangeAlerts: false, powerChangeSound: false) == nil)
		#expect(engine.evaluate(previous: onBattery(22), current: onBattery(20), rules: [below20], powerChangeAlerts: false, powerChangeSound: false)?.kind == .below(threshold: 20))
	}

	@Test func reenablingARuleRearmsIt() {
		var disabled = below20
		disabled.isEnabled = false
		var engine = armed([disabled], at: onBattery(50))
		engine.sync(rules: [below20], state: onBattery(50))
		#expect(engine.evaluate(previous: onBattery(50), current: onBattery(20), rules: [below20], powerChangeAlerts: false, powerChangeSound: false)?.kind == .below(threshold: 20))
	}
}
