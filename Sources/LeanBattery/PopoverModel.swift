import AppKit
import Observation
import LeanBatteryCore

/// Popover state: header and battery info values plus settings. Its 5 s refresh timer runs only while the popover is visible.
@MainActor
@Observable
final class PopoverModel {
	private(set) var header: PowerHeader?
	private(set) var info: BatteryInfo?

	/// What the energy section is currently showing.
	enum EnergyState: Equatable {
		case loading
		case rows([EnergyRow])
		case empty(String)
		case unavailable
	}

	private(set) var energyState: EnergyState = .loading

	/// Selected range. Never persisted: the popover always opens on `Now` (spec §5.2).
	var energyRange: EnergyRange = .now {
		didSet {
			guard energyRange != oldValue else { return }
			energyState = .loading
			refreshEnergy()
		}
	}

	var isShowingSettings = false
	/// Whether the notifications subpage is showing on top of settings (spec §6.1).
	var isShowingNotifications = false
	/// Notification preferences, shared with the presenter that shows the pill.
	@ObservationIgnored let notificationSettings: NotificationSettings
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
	@ObservationIgnored private let onPreviewNotification: () -> Void
	@ObservationIgnored private var timer: Timer?
	/// Reads energy sums from the powerlog; an actor because its work is blocking file/SQLite I/O.
	@ObservationIgnored private let energyStore = EnergyStore()
	/// Seconds of history behind each range, for the short-span segment labels.
	@ObservationIgnored private var energyCoverage: [EnergyRange: Double] = [:]
	/// Generation counter so a slow read can never overwrite a newer one.
	@ObservationIgnored private var energyGeneration = 0

	/// Creates the model from persisted settings.
	init(monitor: BatteryMonitor, notificationSettings: NotificationSettings, onPreviewNotification: @escaping () -> Void) {
		self.monitor = monitor
		self.notificationSettings = notificationSettings
		self.onPreviewNotification = onPreviewNotification
		isInfoExpanded = UserDefaults.standard.bool(forKey: DefaultsKey.batteryInfoExpanded)
		hotThresholdCelsius = UserDefaults.standard.double(forKey: DefaultsKey.hotThresholdCelsius)
		launchAtLogin = LoginItem.isEnabled
		launchAtLoginMessage = LoginItem.statusText
	}

	/// Shows the sample notification behind the `Preview notification` button (spec §6.1).
	func previewNotification() {
		onPreviewNotification()
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

	/// Stops the refresh timer, leaves settings, and releases cached energy data.
	func stop() {
		timer?.invalidate()
		timer = nil
		isShowingSettings = false
		isShowingNotifications = false
		energyRange = .now
		energyState = .loading
		energyCoverage = [:]
		let store = energyStore
		Task { await store.clearCache() }
	}

	/// Re-reads values only while the popover is visible (called on monitor changes).
	func refreshIfVisible() {
		guard timer != nil else { return }
		refresh()
	}

	/// Reads the monitor state and battery registry; Battery Information only when expanded.
	func refresh() {
		monitor.refresh()
		refreshEnergy()
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

	/// Segment title for `range`, shortened when less history exists (e.g. "6d").
	func energyLabel(for range: EnergyRange) -> String {
		guard let covered = energyCoverage[range] else { return range.label }
		return range.label(covering: covered)
	}

	/// Re-reads energy for the selected range on a background actor and publishes the result.
	func refreshEnergy() {
		// Refuse to run while the popover is closed (docs/popover.md: "nothing here runs").
		guard timer != nil else { return }
		energyGeneration += 1
		let generation = energyGeneration
		let range = energyRange
		let store = energyStore
		let now = Date().timeIntervalSince1970
		Task {
			let outcome: Result<EnergySums, Error>
			do {
				outcome = .success(try await store.sums(for: range, now: now))
			} catch {
				outcome = .failure(error)
			}
			// A newer read (or a closed popover) has superseded this one.
			guard generation == energyGeneration, timer != nil, range == energyRange else { return }
			apply(outcome, for: range)
		}
	}

	/// Turns a completed read into display state (spec §5.2, §9).
	/// Every assignment is guarded like `header`/`info` above: without it, `@Observable` would
	/// fire on every 5 s tick even when the state is unchanged, re-rendering the whole energy
	/// section (and re-running `AppCatalog.icon(for:)` for every visible row).
	private func apply(_ outcome: Result<EnergySums, Error>, for range: EnergyRange) {
		guard case .success(let measured) = outcome else {
			if energyState != .unavailable {
				energyState = .unavailable
			}
			return
		}
		energyCoverage[range] = measured.coveredSeconds
		guard !measured.suppressesRows(for: range) else {
			let newState = EnergyState.empty(range.emptyText)
			if energyState != newState {
				energyState = newState
			}
			return
		}
		let rows = EnergyAggregator.rows(
			sums: measured.sums,
			displayName: AppCatalog.displayName(for:),
			isApplication: AppCatalog.isApplication(_:))
		let newState: EnergyState = rows.isEmpty ? .empty(range.emptyText) : .rows(rows)
		if energyState != newState {
			energyState = newState
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
