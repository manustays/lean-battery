import AppKit
import LeanBatteryCore

/// UserDefaults keys used by the app.
enum DefaultsKey {
	static let hotThresholdCelsius = "tempThresholdC"
	static let batteryInfoExpanded = "batteryInfoExpanded"
	static let notificationRules = "notificationRules"
	static let powerChangeAlerts = "powerChangeAlerts"
	static let powerChangeSound = "powerChangeSound"
	static let notificationDuration = "notificationDuration"
	static let pillStyle = "pillStyle"
	static let updateCheckEnabled = "updateCheckEnabled"
	static let updateLastAttempt = "updateLastAttempt"
	static let updateLastSuccess = "updateLastSuccess"
	static let updateRateLimitReset = "updateRateLimitReset"
	static let updateETag = "updateETag"
	static let updateCachedTag = "updateCachedTag"
	static let updateCachedURL = "updateCachedURL"
	static let updateDismissedVersion = "updateDismissedVersion"
}

/// Wires the battery monitor to the menubar icon, the popover, and the notification engine.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	/// Menubar status item and its icon.
	private var statusIcon: StatusIcon?
	/// Publishes battery state changes; drives the icon, the popover, and the rule engine.
	private var monitor: BatteryMonitor?
	/// Popover content and settings state.
	private var popoverModel: PopoverModel?
	/// Owns the popover window and its show/hide behavior.
	private var popoverController: PopoverController?
	/// Notification preferences, shared with the popover's settings subpage and the presenter.
	private var notificationSettings: NotificationSettings?
	/// Shows the pill, the glow, and the alert sound for a fired notification event.
	private var notificationPresenter: NotificationPresenter?
	/// Armed-flag state for the battery rules; memory only (spec §6.2).
	private var ruleEngine = RuleEngine()

	/// Registers defaults, creates the status item, popover, and notification presenter, and starts monitoring.
	func applicationDidFinishLaunching(_ notification: Notification) {
		UserDefaults.standard.register(defaults: [
			DefaultsKey.hotThresholdCelsius: 40.0,
			DefaultsKey.batteryInfoExpanded: false,
			DefaultsKey.notificationDuration: 4,
			DefaultsKey.pillStyle: PillStyle.default.rawValue,
			DefaultsKey.updateCheckEnabled: true,
		])
		let statusIcon = StatusIcon { [weak self] button in
			self?.popoverController?.toggle(relativeTo: button)
		}
		let notificationSettings = NotificationSettings()
		let notificationPresenter = NotificationPresenter(settings: notificationSettings)
		let monitor = BatteryMonitor(hotThresholdCelsius: UserDefaults.standard.double(forKey: DefaultsKey.hotThresholdCelsius)) { [weak self] previous, state in
			statusIcon.update(state)
			self?.popoverModel?.refreshIfVisible()
			self?.evaluateRules(previous: previous, current: state)
		}
		let updates = UpdateService()
		let popoverModel = PopoverModel(
			monitor: monitor,
			notificationSettings: notificationSettings,
			updates: updates,
			onPreviewNotification: { notificationPresenter.preview() })
		// A rule edit must re-arm from the level at edit time, not at the next battery change (spec §6.2).
		notificationSettings.onRulesChange = { [weak self, weak monitor] rules in
			self?.ruleEngine.sync(rules: rules, state: monitor?.state)
		}
		self.statusIcon = statusIcon
		self.monitor = monitor
		self.popoverModel = popoverModel
		self.notificationSettings = notificationSettings
		self.notificationPresenter = notificationPresenter
		popoverController = PopoverController(model: popoverModel)
		monitor.start()
	}

	/// Evaluates the battery rules for a state change and shows the resulting notification.
	private func evaluateRules(previous: BatteryState?, current: BatteryState) {
		guard let notificationSettings, let notificationPresenter else { return }
		guard let event = ruleEngine.evaluate(
			previous: previous,
			current: current,
			rules: notificationSettings.rules,
			powerChangeAlerts: notificationSettings.powerChangeAlerts,
			powerChangeSound: notificationSettings.powerChangeSound)
		else { return }
		notificationPresenter.show(event)
	}
}
