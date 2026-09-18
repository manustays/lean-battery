/// A stable three-part version (spec §13.3): optional leading `v`, exactly three non-negative integers, nothing else.
/// Pre-releases and build metadata are deliberately unparseable — the app must never offer one.
public struct SemanticVersion: Comparable, Equatable, Sendable {
	public let major: Int
	public let minor: Int
	public let patch: Int

	/// Parses `1.2.3` or `v1.2.3`; returns nil for anything else, including overflowing components.
	public init?(_ text: String) {
		var body = Substring(text)
		if body.first == "v" { body = body.dropFirst() }
		let parts = body.split(separator: ".", omittingEmptySubsequences: false)
		guard parts.count == 3 else { return nil }
		var values: [Int] = []
		for part in parts {
			guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber), let value = Int(part) else { return nil }
			values.append(value)
		}
		(major, minor, patch) = (values[0], values[1], values[2])
	}

	public static func < (lhs: Self, rhs: Self) -> Bool {
		(lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
	}
}
