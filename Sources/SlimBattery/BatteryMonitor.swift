import AppKit
import IOKit.ps
import SlimBatteryCore

/// Publishes a BatteryState whenever power source, Low Power Mode, wake, the temperature timer, or the hot threshold yields a change.
@MainActor
final class BatteryMonitor {
	/// Temperature at or above which the state reports hot; changing it re-evaluates immediately.
	var hotThresholdCelsius: Double {
		didSet { refresh() }
	}

	/// Latest published state, or nil before the first successful read.
	private(set) var state: BatteryState?

	private let onChange: @MainActor (_ previous: BatteryState?, _ current: BatteryState) -> Void

	/// Creates a monitor; call `start()` to begin observing. `onChange` receives the previous and new state.
	init(hotThresholdCelsius: Double, onChange: @escaping @MainActor (_ previous: BatteryState?, _ current: BatteryState) -> Void) {
		self.hotThresholdCelsius = hotThresholdCelsius
		self.onChange = onChange
	}

	/// Registers every event source and publishes the initial state.
	/// ponytail: lives for the app's lifetime, so observers and the run loop source are never removed.
	func start() {
		let context = Unmanaged.passUnretained(self).toOpaque()
		if let source = IOPSNotificationCreateRunLoopSource({ context in
			guard let context else { return }
			let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
			MainActor.assumeIsolated { monitor.refresh() }
		}, context)?.takeRetainedValue() {
			CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
		}
		observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange)
		// ponytail: no explicit timer reschedule on wake — an overdue repeating Timer fires on wake and this refresh re-reads everything.
		observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
		// Temperature has no change notification; a lax 60s timer lets macOS coalesce wakeups.
		let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
			guard let self else { return }
			MainActor.assumeIsolated { self.refresh() }
		}
		timer.tolerance = 30
		RunLoop.main.add(timer, forMode: .common)
		refresh()
	}

	/// Reads current power data and publishes it if anything changed.
	func refresh() {
		guard let description = SystemPower.internalBatteryDescription() else { return }
		let registry = SystemPower.smartBatteryProperty("Temperature").map { ["Temperature": $0] } ?? [:]
		guard
			let newState = BatteryState.make(
				powerSource: description,
				registry: registry,
				isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
				hotThresholdCelsius: hotThresholdCelsius
			),
			newState != state
		else { return }
		let previous = state
		state = newState
		onChange(previous, newState)
	}

	/// Calls `refresh()` on the main queue whenever `name` is posted.
	private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
		center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
			guard let self else { return }
			MainActor.assumeIsolated { self.refresh() }
		}
	}
}
