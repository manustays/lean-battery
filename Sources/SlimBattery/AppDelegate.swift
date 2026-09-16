import AppKit
import SlimBatteryCore

/// UserDefaults keys used by the app.
enum DefaultsKey {
	static let hotThresholdCelsius = "tempThresholdC"
}

/// Wires the battery monitor to the menubar icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	private var statusIcon: StatusIcon?
	private var monitor: BatteryMonitor?

	/// Registers defaults, creates the status item and starts monitoring.
	func applicationDidFinishLaunching(_ notification: Notification) {
		UserDefaults.standard.register(defaults: [DefaultsKey.hotThresholdCelsius: 40.0])
		let statusIcon = StatusIcon()
		let monitor = BatteryMonitor(hotThresholdCelsius: UserDefaults.standard.double(forKey: DefaultsKey.hotThresholdCelsius)) { _, state in
			statusIcon.update(state)
		}
		monitor.start()
		self.statusIcon = statusIcon
		self.monitor = monitor
	}
}
