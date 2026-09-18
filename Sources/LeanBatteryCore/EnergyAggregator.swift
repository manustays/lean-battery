import Foundation

/// Turns raw per-`who` energy sums into the popover's display rows (spec §5.2, §8.3).
public enum EnergyAggregator {
	/// Spec §8.3: a non-app item earns a row only by ranking this high overall.
	/// Deliberately independent of `limit`, which caps how many rows are DISPLAYED —
	/// conflating the two is what made the eligibility set wrong before.
	private static let systemItemEligibilityRank = 5

	/// Applies the display rules and returns at most `limit` rows, highest share first.
	///
	/// - Parameters:
	///   - sums: nanojoules per raw powerlog `who` value.
	///   - displayName: resolves a canonical id to a human name (the app layer supplies real app names).
	///   - isApplication: true when the id resolves to an installed `.app`.
	///   - limit: maximum rows displayed; does not affect which items are eligible (see `systemItemEligibilityRank`).
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
		let topIDs = Set(ranked.prefix(systemItemEligibilityRank).map(\.key))

		// Bounded scan: `ranked` can hold ~290 ids and `isApplication` is a ~4 ms main-actor
		// LaunchServices lookup, so an eager `filter` over all of it is a visible popover freeze.
		// Stop as soon as `limit` eligible rows are found; never call `isApplication` twice per id.
		var eligible: [EnergyRow] = []
		eligible.reserveCapacity(limit)
		for entry in ranked {
			guard eligible.count < limit else { break }
			let isApp: Bool
			if topIDs.contains(entry.key) {
				// Already eligible; still need the flag for the row, but the eligibility test itself skipped the lookup.
				isApp = isApplication(entry.key)
			} else {
				isApp = isApplication(entry.key)
				guard isApp else { continue }
			}
			eligible.append(EnergyRow(
				id: entry.key,
				displayName: displayName(entry.key),
				sharePercent: 100 * entry.value / total,
				isApplication: isApp))
		}
		return eligible.filter { $0.sharePercent >= minimumSharePercent }
	}
}
