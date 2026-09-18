import Foundation

/// Decides which notification, if any, a battery state change should show (spec §6.2).
/// Pure: the armed flags live in memory only and are never persisted.
public struct RuleEngine {
	/// How far the level must move back past a threshold before that rule can fire again.
	public static let rearmMargin = 2

	private var armed: [UUID: Bool] = [:]
	private var known: [UUID: NotificationRule] = [:]

	public init() {}

	/// Arms rules that are new, edited, or re-enabled from `state`, and forgets deleted or disabled ones.
	/// Call this as soon as the rule list changes so arming uses the level at edit time, not the level at the next battery change.
	public mutating func sync(rules: [NotificationRule], state: BatteryState?) {
		let enabled = rules.filter(\.isEnabled)
		let ids = Set(enabled.map(\.id))
		armed = armed.filter { ids.contains($0.key) }
		known = known.filter { ids.contains($0.key) }
		// Without a reading there is nothing to arm from; the first sync that has one arms these rules.
		guard let state else { return }
		for rule in enabled {
			let needsArming = known[rule.id].map { rule.armingDiffers(from: $0) } ?? true
			known[rule.id] = rule
			if needsArming {
				armed[rule.id] = Self.initialArming(rule: rule, state: state)
			}
		}
	}

	/// Evaluates one state change and returns at most one event (spec §6.2).
	public mutating func evaluate(
		previous: BatteryState?,
		current: BatteryState,
		rules: [NotificationRule],
		powerChangeAlerts: Bool,
		powerChangeSound: Bool
	) -> NotificationEvent? {
		// A no-op for rules the engine already knows; it only catches lists that changed without a sync.
		sync(rules: rules, state: current)
		// Arming never fires by itself: the first reading after launch is arming material only.
		guard let previous else { return nil }

		var firedBelow: [NotificationRule] = []
		var firedAbove: [NotificationRule] = []
		for rule in rules where rule.isEnabled {
			if rearms(rule: rule, state: current) {
				armed[rule.id] = true
			}
			guard armed[rule.id] == true, fires(rule: rule, state: current) else { continue }
			// Every rule that met its condition disarms, not just the one shown, so a suppressed
			// rule does not fire on the very next change.
			armed[rule.id] = false
			switch rule.direction {
			case .below: firedBelow.append(rule)
			case .above: firedAbove.append(rule)
			}
		}

		if let rule = firedBelow.min(by: { $0.threshold < $1.threshold }) {
			return NotificationEvent(kind: .below(threshold: rule.threshold), state: current, showsGlow: rule.glow, playsSound: rule.sound)
		}
		if let rule = firedAbove.max(by: { $0.threshold < $1.threshold }) {
			// Spec §6.1: glow is a below-rule option only.
			return NotificationEvent(kind: .above(threshold: rule.threshold), state: current, showsGlow: false, playsSound: rule.sound)
		}
		guard powerChangeAlerts, previous.isPluggedIn != current.isPluggedIn else { return nil }
		return NotificationEvent(kind: .powerChange, state: current, showsGlow: false, playsSound: powerChangeSound)
	}

	/// Below arms unless the level is already at or under the threshold on battery; above arms only under the threshold.
	private static func initialArming(rule: NotificationRule, state: BatteryState) -> Bool {
		switch rule.direction {
		case .below: state.isPluggedIn || state.percent > rule.threshold
		case .above: state.percent < rule.threshold
		}
	}

	/// Below fires on battery at or under the threshold; above fires on adapter power at or over it.
	private func fires(rule: NotificationRule, state: BatteryState) -> Bool {
		switch rule.direction {
		case .below: !state.isPluggedIn && state.percent <= rule.threshold
		case .above: state.isPluggedIn && state.percent >= rule.threshold
		}
	}

	/// Below re-arms on plug-in or a two-point climb; above re-arms only after a two-point drop.
	private func rearms(rule: NotificationRule, state: BatteryState) -> Bool {
		switch rule.direction {
		case .below: state.isPluggedIn || state.percent >= rule.threshold + Self.rearmMargin
		case .above: state.percent <= rule.threshold - Self.rearmMargin
		}
	}
}
