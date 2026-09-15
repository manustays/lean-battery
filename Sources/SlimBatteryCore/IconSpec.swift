/// What the menubar icon shows for a battery state (spec §4.2). Equatable so redraws happen only on visible change.
public struct IconSpec: Equatable, Sendable {
	/// Fill color role, resolved to a concrete color by the renderer.
	public enum Fill: Equatable, Sendable {
		case foreground
		case lowPower
		case charging
		case low
	}

	/// Content drawn inside the battery body.
	public enum Glyph: Equatable, Sendable {
		case number(Int)
		case plug
	}

	/// Charge level at or below which the fill turns red.
	public static let lowPercent = 20

	/// Fraction of the inner area to fill, 0–1.
	public var fillFraction: Double
	public var fill: Fill
	public var glyph: Glyph
	public var showsHotBadge: Bool

	/// Derives the icon spec from a battery state.
	public init(state: BatteryState) {
		fillFraction = Double(min(100, max(0, state.percent))) / 100
		if state.isLowPowerMode {
			fill = .lowPower
		} else if state.isCharging {
			fill = .charging
		} else if state.percent <= Self.lowPercent {
			fill = .low
		} else {
			fill = .foreground
		}
		glyph = state.isPluggedIn ? .plug : .number(state.percent)
		showsHotBadge = state.isHot
	}

	/// Point size of the number glyph; smaller for three digits.
	public var numberFontSize: Double {
		glyph == .number(100) ? 5.6 : 7.8
	}
}
