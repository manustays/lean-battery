import AppKit
import IOKit.ps
import SlimBatteryCore

/// Publishes a BatteryState whenever power source, Low Power Mode, wake, or the temperature timer yields a change.
@MainActor
final class BatteryMonitor {
	private let hotThresholdCelsius: Double
	private let onChange: @MainActor (BatteryState) -> Void
	private var lastState: BatteryState?

	/// Creates a monitor; call `start()` to begin observing.
	init(hotThresholdCelsius: Double, onChange: @escaping @MainActor (BatteryState) -> Void) {
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
			let state = BatteryState.make(
				powerSource: description,
				registry: registry,
				isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
				hotThresholdCelsius: hotThresholdCelsius
			),
			state != lastState
		else { return }
		lastState = state
		onChange(state)
	}

	/// Calls `refresh()` on the main queue whenever `name` is posted.
	private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
		center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
			guard let self else { return }
			MainActor.assumeIsolated { self.refresh() }
		}
	}
}
