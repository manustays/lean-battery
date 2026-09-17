/// How large the notification pill is drawn, and whether it hangs below the menubar or hugs the screen's top edge.
public enum PillStyle: String, Codable, CaseIterable, Equatable, Sendable {
	case small
	case medium
	case large
	/// Flush to the top edge, like a body grown out of the display's notch.
	case notch

	/// The style a fresh install uses.
	public static let `default` = PillStyle.medium

	/// Reads a persisted raw value, falling back to the default for anything unrecognised.
	public init(stored: String?) {
		self = stored.flatMap(PillStyle.init(rawValue:)) ?? .default
	}

	/// Label shown in the settings picker.
	public var title: String {
		switch self {
		case .small: "Small"
		case .medium: "Default"
		case .large: "Large"
		case .notch: "Notch"
		}
	}

	/// Multiplier applied to the default geometry. `notch` carries its own dimensions instead.
	var scale: Double {
		switch self {
		case .small: 0.85
		case .medium: 1.0
		case .large: 1.2
		case .notch: 1.0
		}
	}
}

/// Every dimension the pill is drawn with, derived from a `PillStyle` so the view holds no geometry of its own.
public struct PillMetrics: Equatable, Sendable {
	/// Height of the pill body.
	public var height: Double
	/// Narrowest the body is allowed to shrink to.
	public var minimumWidth: Double
	/// Widest the body may grow before its text truncates.
	public var maximumWidth: Double
	/// Battery glyph width; the glyph is always twice as tall as it is wide.
	public var iconWidth: Double
	/// Battery glyph height.
	public var iconHeight: Double
	/// Point size of the title line.
	public var titleFontSize: Double
	/// Point size of the detail line.
	public var detailFontSize: Double
	/// Padding inside the body's leading and trailing edges.
	public var horizontalPadding: Double
	/// Gap between the battery glyph and the text column.
	public var contentSpacing: Double
	/// Corner radius of the body. Half the height makes a capsule.
	public var cornerRadius: Double
	/// Distance between the menubar band and the top of the body.
	public var topGap: Double
	/// True when the body sits flush against the screen's top edge with square top corners (the notch style).
	public var hugsTopEdge: Bool

	/// Width the notch style reveals from on a display whose real notch width is unknown.
	public static let notchStubWidth: Double = 180

	/// Default geometry, scaled by the style, except for `notch` which has dimensions of its own.
	public init(style: PillStyle) {
		if style == .notch {
			height = 42
			minimumWidth = 260
			maximumWidth = 420
			iconWidth = 10
			iconHeight = 20
			titleFontSize = 12.5
			detailFontSize = 11
			horizontalPadding = 14
			contentSpacing = 9
			// Rounded along the bottom only, so the top reads as a continuation of the screen edge.
			cornerRadius = 18
			topGap = 0
			hugsTopEdge = true
			return
		}
		let scale = style.scale
		height = 46 * scale
		minimumWidth = 240 * scale
		maximumWidth = 400 * scale
		// The glyph is rendered at 11 x 22 pt (1x and 2x), so drawing it any larger upscales that bitmap
		// and softens it. Small shrinks it; Large keeps it at native size and grows only the text and box.
		iconWidth = min(11 * scale, 11)
		iconHeight = iconWidth * 2
		titleFontSize = 13 * scale
		detailFontSize = 11.5 * scale
		horizontalPadding = 16 * scale
		contentSpacing = 10 * scale
		cornerRadius = height / 2
		topGap = 8
		hugsTopEdge = false
	}
}
