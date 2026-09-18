import Foundation

/// Snapshot of the internal battery, built from IOPS and AppleSmartBattery data.
public struct BatteryState: Equatable, Sendable {
	/// Charge level, 0–100.
	public var percent: Int
	/// True while the battery is actively charging.
	public var isCharging: Bool
	/// True when external power is connected (charging or not).
	public var isPluggedIn: Bool
	/// Minutes to empty (on battery) or to full (plugged in); nil while macOS is calculating.
	public var minutesRemaining: Int?
	/// True when Low Power Mode is on.
	public var isLowPowerMode: Bool
	/// Battery temperature in °C; nil when the registry key is missing.
	public var temperatureCelsius: Double?
	/// True when the temperature is at or above the user's threshold.
	public var isHot: Bool

	/// Creates a state from explicit values.
	public init(
		percent: Int,
		isCharging: Bool = false,
		isPluggedIn: Bool = false,
		minutesRemaining: Int? = nil,
		isLowPowerMode: Bool = false,
		temperatureCelsius: Double? = nil,
		isHot: Bool = false
	) {
		self.percent = percent
		self.isCharging = isCharging
		self.isPluggedIn = isPluggedIn
		self.minutesRemaining = minutesRemaining
		self.isLowPowerMode = isLowPowerMode
		self.temperatureCelsius = temperatureCelsius
		self.isHot = isHot
	}

	/// Builds a state from an IOPS power source description and AppleSmartBattery registry properties.
	/// Returns nil when the description has no usable capacity (e.g. no battery).
	public static func make(
		powerSource: [String: Any],
		registry: [String: Any],
		isLowPowerMode: Bool,
		hotThresholdCelsius: Double
	) -> BatteryState? {
		guard
			let current = powerSource["Current Capacity"] as? Int,
			let maximum = powerSource["Max Capacity"] as? Int,
			maximum > 0
		else { return nil }
		let percent = min(100, max(0, Int((Double(current) * 100 / Double(maximum)).rounded())))
		let isPluggedIn = (powerSource["Power Source State"] as? String) == "AC Power"
		let minutesKey = isPluggedIn ? "Time to Full Charge" : "Time to Empty"
		let minutes = (powerSource[minutesKey] as? Int).flatMap { $0 >= 0 ? $0 : nil }
		let temperature = (registry["Temperature"] as? Int).map { Double($0) / 100 }
		return BatteryState(
			percent: percent,
			isCharging: (powerSource["Is Charging"] as? Bool) ?? false,
			isPluggedIn: isPluggedIn,
			minutesRemaining: minutes,
			isLowPowerMode: isLowPowerMode,
			temperatureCelsius: temperature,
			isHot: temperature.map { $0 >= hotThresholdCelsius } ?? false
		)
	}

	/// VoiceOver label for the menubar icon, e.g. "Battery 57%, charging, hot".
	public var accessibilityDescription: String {
		var parts = ["Battery \(percent)%"]
		if isCharging {
			parts.append("charging")
		} else if isPluggedIn {
			parts.append("plugged in, not charging")
		}
		if isLowPowerMode { parts.append("Low Power Mode") }
		if isHot { parts.append("hot") }
		return parts.joined(separator: ", ")
	}
}
