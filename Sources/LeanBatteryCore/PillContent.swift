/// The pill's two text lines for an event (spec §6.3 content table).
public struct PillContent: Equatable, Sendable {
	/// First line: the main event description.
	public var title: String
	/// Second line: the battery, power source, or time details.
	public var detail: String

	/// Builds the lines; `adapterWatts` comes from `AdapterDetails.Watts` and is nil when unknown or on battery.
	public init(event: NotificationEvent, adapterWatts: Int?) {
		let state = event.state
		switch event.kind {
		case .below:
			title = "Low Battery"
			detail = state.minutesRemaining
				.map { "\(state.percent)% · about \(Self.remaining(minutes: $0)) left" } ?? "\(state.percent)%"
		case .above(let threshold):
			title = "Charged to \(threshold)%"
			// Spec §6.3: an above-rule pill with unknown wattage says "Plugged In", not "Power Adapter".
			detail = adapterWatts.map { "Power Adapter · \($0) W" } ?? "Plugged In"
		case .powerChange where state.isPluggedIn && state.isCharging:
			title = "Charging · \(state.percent)%"
			let toFull = state.minutesRemaining.map { " · \(PowerHeader.duration(minutes: $0)) to full" } ?? ""
			detail = Self.adapterText(adapterWatts) + toFull
		case .powerChange where state.isPluggedIn:
			title = "Plugged In · Not Charging"
			detail = "\(state.percent)%"
		case .powerChange:
			title = "On Battery · \(state.percent)%"
			detail = state.minutesRemaining
				.map { "About \(Self.remaining(minutes: $0)) left" } ?? "Calculating time left…"
		}
	}

	/// "38m" under an hour, otherwise "4h 05m".
	static func remaining(minutes: Int) -> String {
		minutes < 60 ? "\(minutes)m" : PowerHeader.duration(minutes: minutes)
	}

	/// "Power Adapter · 96 W", or "Power Adapter" when the wattage is unknown.
	private static func adapterText(_ watts: Int?) -> String {
		watts.map { "Power Adapter · \($0) W" } ?? "Power Adapter"
	}
}
