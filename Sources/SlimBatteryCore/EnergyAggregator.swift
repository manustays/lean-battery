import Foundation

/// Turns raw per-`who` energy sums into the popover's display rows (spec §5.2, §8.3).
public enum EnergyAggregator {
	/// Applies the display rules and returns at most `limit` rows, highest share first.
	///
	/// - Parameters:
	///   - sums: nanojoules per raw powerlog `who` value.
	///   - displayName: resolves a canonical id to a human name (the app layer supplies real app names).
	///   - isApplication: true when the id resolves to an installed `.app`.
	///   - limit: maximum rows shown.
	///   - minimumSharePercent: rows below this share are dropped.
	public static func rows(
		sums: [String: Double],
		displayName: (String) -> String,
		isApplication: (String) -> Bool,
		limit: Int = 5,
		minimumSharePercent: Double = 1
	) -> [EnergyRow] {
		// Drop junk, then merge ids that differ only by a trailing UUID.
		var merged: [String: Double] = [:]
		for (who, energy) in sums where !EnergyName.isJunk(who) && energy > 0 {
			merged[EnergyName.canonical(who), default: 0] += energy
		}
		let total = merged.values.reduce(0, +)
		guard total > 0 else { return [] }

		// Rank everything once: ties break on id so the order is stable between ticks.
		let ranked = merged.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
		// A system item earns a place only by ranking in the overall top 5; an app always qualifies.
		let topIDs = Set(ranked.prefix(5).map(\.key))

		return ranked
			.filter { isApplication($0.key) || topIDs.contains($0.key) }
			.prefix(limit)
			.map { EnergyRow(
				id: $0.key,
				displayName: displayName($0.key),
				sharePercent: 100 * $0.value / total,
				isApplication: isApplication($0.key)) }
			.filter { $0.sharePercent >= minimumSharePercent }
	}
}
