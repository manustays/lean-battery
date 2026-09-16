import Foundation

/// The popover's energy time ranges (spec §5.2). Never persisted: the popover always opens on `.now`.
public enum EnergyRange: String, CaseIterable, Sendable, Identifiable {
	case now
	case eightHours
	case day
	case week

	public var id: String { rawValue }

	/// Window length in seconds.
	public var seconds: Double {
		switch self {
		case .now: 300
		case .eightHours: 28_800
		case .day: 86_400
		case .week: 604_800
		}
	}

	/// Segment title when the log covers the whole range.
	public var label: String {
		switch self {
		case .now: "Now"
		case .eightHours: "8h"
		case .day: "24h"
		case .week: "7d"
		}
	}

	/// Segment title for `covered` seconds of real history: the full label, or the real span (e.g. "6d").
	/// Archives roll off daily, so a 7 d selection routinely has less than 7 d behind it.
	public func label(covering covered: Double) -> String {
		guard covered < seconds - 1 else { return label }
		if covered >= 86_400 { return "\(Int(covered / 86_400))d" }
		if covered >= 3_600 { return "\(Int(covered / 3_600))h" }
		return "\(max(1, Int(covered / 60)))m"
	}

	/// Text shown when the range produced no rows.
	public var emptyText: String {
		self == .now ? "No activity in the last 5 min" : "No data for this range"
	}
}
