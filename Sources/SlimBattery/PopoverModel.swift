import AppKit
import Observation
import SlimBatteryCore

/// Popover state: header and battery info values plus settings. Its 5 s refresh timer runs only while the popover is visible.
@MainActor
@Observable
final class PopoverModel {
	private(set) var header: PowerHeader?
	private(set) var info: BatteryInfo?
	var isShowingSettings = false
	private(set) var isChangingLowPowerMode = false
	private(set) var lowPowerModeMessage: String?
	private(set) var launchAtLogin: Bool
	private(set) var launchAtLoginMessage: String?

	/// Whether Battery Information is expanded; persisted, and data is read only while expanded.
	var isInfoExpanded: Bool {
		didSet {
			UserDefaults.standard.set(isInfoExpanded, forKey: DefaultsKey.batteryInfoExpanded)
			if isInfoExpanded { refresh() }
		}
	}

	/// Hot badge threshold in °C; persisted and pushed to the monitor.
	var hotThresholdCelsius: Double {
		didSet {
			UserDefaults.standard.set(hotThresholdCelsius, forKey: DefaultsKey.hotThresholdCelsius)
			monitor.hotThresholdCelsius = hotThresholdCelsius
			refresh()
		}
	}

	@ObservationIgnored private let monitor: BatteryMonitor
	@ObservationIgnored private var timer: Timer?

	/// Creates the model from persisted settings.
	init(monitor: BatteryMonitor) {
		self.monitor = monitor
		isInfoExpanded = UserDefaults.standard.bool(forKey: DefaultsKey.batteryInfoExpanded)
		hotThresholdCelsius = UserDefaults.standard.double(forKey: DefaultsKey.hotThresholdCelsius)
		launchAtLogin = LoginItem.isEnabled
		launchAtLoginMessage = LoginItem.statusText
	}

	/// Refreshes now and every 5 s until `stop()`.
	func start() {
		launchAtLogin = LoginItem.isEnabled
		launchAtLoginMessage = LoginItem.statusText
		refresh()
		guard timer == nil else { return }
		let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
			guard let self else { return }
			MainActor.assumeIsolated { self.refresh() }
		}
		timer.tolerance = 1
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
	}

	/// Stops the refresh timer and leaves settings.
	func stop() {
		timer?.invalidate()
		timer = nil
		isShowingSettings = false
	}

	/// Re-reads values only while the popover is visible (called on monitor changes).
	func refreshIfVisible() {
		guard timer != nil else { return }
		refresh()
	}

	/// Reads the monitor state and battery registry; Battery Information only when expanded.
	func refresh() {
		monitor.refresh()
		guard let state = monitor.state else {
			header = nil
			info = nil
			return
		}
		let registry = SystemPower.smartBatteryProperties()
		let newHeader = PowerHeader(state: state, registry: registry)
		// Both values are Equatable: assigning only on change keeps @Observable from re-rendering every tick.
		if newHeader != header {
			header = newHeader
		}
		if isInfoExpanded, let description = SystemPower.internalBatteryDescription() {
			let newInfo = BatteryInfo(powerSource: description, registry: registry)
			if newInfo != info {
				info = newInfo
			}
		}
	}

	/// Runs the admin-prompt toggle; the header follows the real state via the monitor's notification.
	func setLowPowerMode(_ enabled: Bool) {
		guard !isChangingLowPowerMode else { return }
		isChangingLowPowerMode = true
		lowPowerModeMessage = nil
		Task {
			let outcome = await LowPowerToggle.set(enabled)
			isChangingLowPowerMode = false
			if case .failed(let message) = outcome {
				lowPowerModeMessage = "Couldn't change Low Power Mode: \(message)"
			}
			refresh()
		}
	}

	/// Applies the launch-at-login switch and shows any error or approval note.
	func setLaunchAtLogin(_ enabled: Bool) {
		let error = LoginItem.setEnabled(enabled)
		launchAtLogin = LoginItem.isEnabled
		launchAtLoginMessage = error ?? LoginItem.statusText
	}
}
