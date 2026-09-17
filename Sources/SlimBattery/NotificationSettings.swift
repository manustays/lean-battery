import Foundation
import Observation
import SlimBatteryCore

/// Notification preferences backed by UserDefaults (spec §6.1); shared by the settings subpage and the presenter.
@MainActor
@Observable
final class NotificationSettings {
	/// Seconds a notification stays on screen; the slider's range (spec §6.1).
	static let durationRange = 2...10

	/// Battery threshold rules, capped at `NotificationRule.maximumCount`.
	var rules: [NotificationRule] {
		didSet {
			guard rules != oldValue else { return }
			UserDefaults.standard.set(NotificationRule.encode(rules), forKey: DefaultsKey.notificationRules)
			onRulesChange?(rules)
		}
	}

	/// Notify when the power adapter is connected or disconnected.
	var powerChangeAlerts: Bool {
		didSet { UserDefaults.standard.set(powerChangeAlerts, forKey: DefaultsKey.powerChangeAlerts) }
	}

	/// Play the alert sound with power-change notifications.
	var powerChangeSound: Bool {
		didSet { UserDefaults.standard.set(powerChangeSound, forKey: DefaultsKey.powerChangeSound) }
	}

	/// How long every notification stays on screen, in seconds.
	var duration: Int {
		didSet { UserDefaults.standard.set(duration, forKey: DefaultsKey.notificationDuration) }
	}

	/// Size and placement of the notification pill.
	var pillStyle: PillStyle {
		didSet { UserDefaults.standard.set(pillStyle.rawValue, forKey: DefaultsKey.pillStyle) }
	}

	/// Called after any rule edit so the engine re-arms from the current level (spec §6.2).
	@ObservationIgnored var onRulesChange: (([NotificationRule]) -> Void)?

	/// Loads persisted values; unreadable rules fall back to the first-launch set (spec §9).
	init() {
		rules = NotificationRule.decode(UserDefaults.standard.data(forKey: DefaultsKey.notificationRules))
		powerChangeAlerts = UserDefaults.standard.bool(forKey: DefaultsKey.powerChangeAlerts)
		powerChangeSound = UserDefaults.standard.bool(forKey: DefaultsKey.powerChangeSound)
		duration = UserDefaults.standard.integer(forKey: DefaultsKey.notificationDuration)
		pillStyle = PillStyle(stored: UserDefaults.standard.string(forKey: DefaultsKey.pillStyle))
	}

	/// Whether another rule fits (spec §6.1 caps at 5).
	var canAddRule: Bool { rules.count < NotificationRule.maximumCount }

	/// Appends a `Below 20%` rule when there is room.
	func addRule() {
		guard canAddRule else { return }
		rules.append(NotificationRule())
	}

	/// Deletes the rule with `id`.
	func removeRule(id: UUID) {
		rules.removeAll { $0.id == id }
	}
}
