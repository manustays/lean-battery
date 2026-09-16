import AppKit
import SlimBatteryCore

/// UserDefaults keys used by the app.
enum DefaultsKey {
	static let hotThresholdCelsius = "tempThresholdC"
	static let batteryInfoExpanded = "batteryInfoExpanded"
}

/// Wires the battery monitor to the menubar icon and the popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	private var statusIcon: StatusIcon?
	private var monitor: BatteryMonitor?
	private var popoverModel: PopoverModel?
	private var popoverController: PopoverController?

	/// Registers defaults, creates the status item and popover, and starts monitoring.
	func applicationDidFinishLaunching(_ notification: Notification) {
		UserDefaults.standard.register(defaults: [
			DefaultsKey.hotThresholdCelsius: 40.0,
			DefaultsKey.batteryInfoExpanded: false,
		])
		let statusIcon = StatusIcon { [weak self] button in
			self?.popoverController?.toggle(relativeTo: button)
		}
		let monitor = BatteryMonitor(hotThresholdCelsius: UserDefaults.standard.double(forKey: DefaultsKey.hotThresholdCelsius)) { [weak self] _, state in
			statusIcon.update(state)
			self?.popoverModel?.refreshIfVisible()
		}
		let popoverModel = PopoverModel(monitor: monitor)
		self.statusIcon = statusIcon
		self.monitor = monitor
		self.popoverModel = popoverModel
		popoverController = PopoverController(model: popoverModel)
		monitor.start()
	}
}
