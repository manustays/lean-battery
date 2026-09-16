import Foundation

/// Parses powerlog `who` values (a bundle id, or a launchd name when the bundle id is empty).
///
/// Grounded in the 290 distinct values on a real Mac (2026-09-16): the only malformed value is the
/// literal `$(PRODUCT_BUNDLE_IDENTIFIER)`, three values carry a trailing UUID, and the spec's
/// `application.<bundleId>.<n>.<n>` form does not occur at all — so it is not parsed.
public enum EnergyName {
	/// True for values that are not real identifiers and must never reach the list.
	public static func isJunk(_ who: String) -> Bool {
		who.isEmpty || who.contains("$") || who.contains("(")
	}

	/// Strips a trailing UUID component so per-instance ids merge
	/// (`com.apple.Safari.WebApp.<UUID>` → `com.apple.Safari.WebApp`).
	public static func canonical(_ who: String) -> String {
		let parts = who.split(separator: ".", omittingEmptySubsequences: false)
		guard parts.count > 1, let last = parts.last, isUUID(String(last)) else { return who }
		return parts.dropLast().joined(separator: ".")
	}

	/// Display name for an id that does not resolve to an installed app.
	public static func fallbackDisplayName(for id: String) -> String {
		if id.hasPrefix("com.apple.") {
			let rest = String(id.dropFirst("com.apple.".count))
			return rest.isEmpty ? id : rest
		}
		return id.split(separator: ".").last.map(String.init) ?? id
	}

	/// 8-4-4-4-12 hexadecimal.
	private static func isUUID(_ value: String) -> Bool {
		let groups = value.split(separator: "-", omittingEmptySubsequences: false)
		guard groups.count == 5 else { return false }
		for (group, length) in zip(groups, [8, 4, 4, 4, 12]) {
			guard group.count == length, group.allSatisfy(\.isHexDigit) else { return false }
		}
		return true
	}
}
