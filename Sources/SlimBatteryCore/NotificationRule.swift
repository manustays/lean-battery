import Foundation

/// A battery threshold notification rule (spec §6.1), persisted as JSON in UserDefaults.
public struct NotificationRule: Codable, Equatable, Identifiable, Sendable {
	/// Which side of the threshold fires.
	public enum Direction: String, Codable, Equatable, Sendable {
		case below
		case above
	}

	/// Most rules the UI offers and storage keeps (spec §6.1).
	public static let maximumCount = 5
	/// Thresholds the stepper allows.
	public static let thresholdRange = 1...99

	public var id: UUID
	public var isEnabled: Bool
	public var direction: Direction
	/// Charge level, in percent, that fires the rule.
	public var threshold: Int
	/// Show the screen-edge glow with this rule's pill (below rules only).
	public var glow: Bool
	/// Play the system alert sound with this rule's pill.
	public var sound: Bool

	/// Creates a rule; the defaults are what `＋ Add rule` inserts (spec §6.1).
	public init(
		id: UUID = UUID(),
		isEnabled: Bool = true,
		direction: Direction = .below,
		threshold: Int = 20,
		glow: Bool = false,
		sound: Bool = false
	) {
		self.id = id
		self.isEnabled = isEnabled
		self.direction = direction
		self.threshold = threshold
		self.glow = glow
		self.sound = sound
	}

	/// What a fresh install starts with: one `Below 20%` rule with glow and sound on (spec §6.1).
	public static var firstLaunchDefaults: [NotificationRule] {
		[NotificationRule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, direction: .below, threshold: 20, glow: true, sound: true)]
	}

	/// Decodes stored rules; unreadable data falls back to the first-launch set and extras are dropped (spec §9).
	public static func decode(_ data: Data?) -> [NotificationRule] {
		guard
			let data,
			let rules = try? JSONDecoder().decode([NotificationRule].self, from: data)
		else { return firstLaunchDefaults }
		return Array(rules.prefix(maximumCount))
	}

	/// Encodes rules for UserDefaults, capped at `maximumCount`.
	public static func encode(_ rules: [NotificationRule]) -> Data? {
		try? JSONEncoder().encode(Array(rules.prefix(maximumCount)))
	}

	/// True when a field that decides arming changed, so the rule must be re-armed (spec §6.2).
	func armingDiffers(from other: NotificationRule) -> Bool {
		isEnabled != other.isEnabled || direction != other.direction || threshold != other.threshold
	}
}
