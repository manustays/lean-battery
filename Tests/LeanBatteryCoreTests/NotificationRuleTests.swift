import Foundation
import Testing
@testable import LeanBatteryCore

@Suite struct NotificationRuleTests {
	@Test func firstLaunchDefaultsAreOneBelowTwentyRuleWithGlowAndSound() {
		let rules = NotificationRule.firstLaunchDefaults
		#expect(rules.count == 1)
		#expect(rules[0].direction == .below)
		#expect(rules[0].threshold == 20)
		#expect(rules[0].isEnabled)
		#expect(rules[0].glow)
		#expect(rules[0].sound)
	}

	@Test func newRuleIsBelowTwentyWithoutGlowOrSound() {
		let rule = NotificationRule()
		#expect(rule.direction == .below)
		#expect(rule.threshold == 20)
		#expect(rule.isEnabled)
		#expect(!rule.glow)
		#expect(!rule.sound)
	}

	@Test func encodeThenDecodeRoundTrips() {
		let rules = [
			NotificationRule(direction: .below, threshold: 15, glow: true, sound: false),
			NotificationRule(isEnabled: false, direction: .above, threshold: 80, glow: false, sound: true),
		]
		#expect(NotificationRule.decode(NotificationRule.encode(rules)) == rules)
	}

	@Test func undecodableDataFallsBackToFirstLaunchDefaults() {
		#expect(NotificationRule.decode(Data("not json".utf8)) == NotificationRule.firstLaunchDefaults)
	}

	@Test func missingDataFallsBackToFirstLaunchDefaults() {
		#expect(NotificationRule.decode(nil) == NotificationRule.firstLaunchDefaults)
	}

	@Test func emptyStoredListStaysEmpty() {
		#expect(NotificationRule.decode(NotificationRule.encode([])) == [])
	}

	@Test func decodeKeepsOnlyTheFirstFiveRules() {
		let rules = (1...7).map { NotificationRule(threshold: $0 * 10) }
		let decoded = NotificationRule.decode(NotificationRule.encode(rules))
		#expect(decoded.count == 5)
		#expect(decoded.map(\.threshold) == [10, 20, 30, 40, 50])
	}

	@Test func armingDiffersOnlyForEnabledDirectionAndThreshold() {
		let rule = NotificationRule(direction: .below, threshold: 20, glow: false, sound: false)
		var sameArming = rule
		sameArming.glow = true
		sameArming.sound = true
		#expect(!rule.armingDiffers(from: sameArming))

		var moved = rule
		moved.threshold = 25
		#expect(rule.armingDiffers(from: moved))

		var flipped = rule
		flipped.direction = .above
		#expect(rule.armingDiffers(from: flipped))

		var disabled = rule
		disabled.isEnabled = false
		#expect(rule.armingDiffers(from: disabled))
	}
}
