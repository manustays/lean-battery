import Foundation

/// One app row in the popover's energy list (spec §5.2).
public struct EnergyRow: Equatable, Sendable, Identifiable {
	/// Canonical identifier — a bundle id where one exists, otherwise a launchd name.
	public let id: String
	public let displayName: String
	/// Share of the range's total energy, 0...100.
	public let sharePercent: Double
	/// True when the id resolves to an installed `.app`; drives the icon.
	public let isApplication: Bool

	public init(id: String, displayName: String, sharePercent: Double, isApplication: Bool) {
		self.id = id
		self.displayName = displayName
		self.sharePercent = sharePercent
		self.isApplication = isApplication
	}

	/// Bar color role (spec §5.2).
	public enum BarLevel: Sendable, Equatable { case high, medium, low }

	/// ≥ 40 % orange, ≥ 15 % yellow, else secondary gray.
	public var barLevel: BarLevel {
		if sharePercent >= 40 { return .high }
		if sharePercent >= 15 { return .medium }
		return .low
	}
}
