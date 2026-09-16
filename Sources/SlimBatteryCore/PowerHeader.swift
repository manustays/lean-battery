import Foundation

/// Display values for the popover's battery header (spec §5.1), built from the monitor's state and AppleSmartBattery properties.
public struct PowerHeader: Equatable, Sendable {
	public var percentText: String
	public var statusLine: String
	public var sourceText: String
	public var drawText: String
	public var temperatureText: String
	public var isHot: Bool
	public var fill: IconSpec.Fill
	public var fillFraction: Double
	public var isLowPowerMode: Bool
	public var lowPowerModeText: String

	/// Builds header values; missing registry values show "—".
	public init(state: BatteryState, registry: [String: Any]) {
		percentText = "\(state.percent)%"
		statusLine = Self.statusLine(for: state)
		sourceText = state.isPluggedIn ? Self.adapterText(registry) : "Battery"
		let milliwatts = (registry["PowerTelemetryData"] as? [String: Any])?["SystemLoad"] as? Int
		drawText = milliwatts.map { String(format: "%.1f W", Double($0) / 1000) } ?? "—"
		temperatureText = state.temperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "—"
		isHot = state.isHot
		let spec = IconSpec(state: state)
		fill = spec.fill
		fillFraction = spec.fillFraction
		isLowPowerMode = state.isLowPowerMode
		lowPowerModeText = state.isLowPowerMode ? "Low Power" : "Automatic"
	}

	/// Formats minutes as hours and zero-padded minutes, e.g. 245 → "4h 05m".
	public static func duration(minutes: Int) -> String {
		String(format: "%dh %02dm", minutes / 60, minutes % 60)
	}

	/// Status subline: charging, plugged-in hold, on battery, or calculating.
	private static func statusLine(for state: BatteryState) -> String {
		if state.isPluggedIn && !state.isCharging { return "Plugged In · Not Charging" }
		guard let minutes = state.minutesRemaining else { return "Calculating…" }
		return state.isCharging ? "Charging · \(duration(minutes: minutes)) to full" : "On Battery · \(duration(minutes: minutes)) left"
	}

	/// "Adapter · 96 W", or "Adapter" when the wattage is unknown (short enough for the 320 pt header grid).
	private static func adapterText(_ registry: [String: Any]) -> String {
		guard let watts = (registry["AdapterDetails"] as? [String: Any])?["Watts"] as? Int, watts > 0 else { return "Adapter" }
		return "Adapter · \(watts) W"
	}
}
