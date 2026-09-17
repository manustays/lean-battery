import AppKit
import SlimBatteryCore

/// UserDefaults keys used by the app.
enum DefaultsKey {
	static let hotThresholdCelsius = "tempThresholdC"
	static let batteryInfoExpanded = "batteryInfoExpanded"
	static let notificationRules = "notificationRules"
	static let powerChangeAlerts = "powerChangeAlerts"
	static let powerChangeSound = "powerChangeSound"
	static let notificationDuration = "notificationDuration"
}

/// Wires the battery monitor to the menubar icon and the popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	private var statusIcon: StatusIcon?
	private var monitor: BatteryMonitor?
	private var popoverModel: PopoverModel?
	private var popoverController: PopoverController?
	private var notificationSettings: NotificationSettings?

	/// Registers defaults, creates the status item and popover, and starts monitoring.
	func applicationDidFinishLaunching(_ notification: Notification) {
		UserDefaults.standard.register(defaults: [
			DefaultsKey.hotThresholdCelsius: 40.0,
			DefaultsKey.batteryInfoExpanded: false,
			DefaultsKey.notificationDuration: 4,
		])
		let statusIcon = StatusIcon { [weak self] button in
			self?.popoverController?.toggle(relativeTo: button)
		}
		let monitor = BatteryMonitor(hotThresholdCelsius: UserDefaults.standard.double(forKey: DefaultsKey.hotThresholdCelsius)) { [weak self] _, state in
			statusIcon.update(state)
			self?.popoverModel?.refreshIfVisible()
		}
		let notificationSettings = NotificationSettings()
		let popoverModel = PopoverModel(monitor: monitor, notificationSettings: notificationSettings, onPreviewNotification: {})
		self.notificationSettings = notificationSettings
		self.statusIcon = statusIcon
		self.monitor = monitor
		self.popoverModel = popoverModel
		popoverController = PopoverController(model: popoverModel)
		monitor.start()
	}
}
