/// One thing to show on screen, produced by `RuleEngine` (spec §6.2).
public struct NotificationEvent: Equatable, Sendable {
	/// Why the event fired; the threshold travels with it for the pill's title.
	public enum Kind: Equatable, Sendable {
		case below(threshold: Int)
		case above(threshold: Int)
		case powerChange
	}

	/// Why the event fired; the threshold travels with it for the pill's title.
	public var kind: Kind
	/// Battery state at the moment the event fired; the pill's icon and text come from it.
	public var state: BatteryState
	/// Show the screen-edge glow (below rules with glow on, and Preview).
	public var showsGlow: Bool
	/// Play the system alert sound once.
	public var playsSound: Bool

	/// Creates an event.
	public init(kind: Kind, state: BatteryState, showsGlow: Bool, playsSound: Bool) {
		self.kind = kind
		self.state = state
		self.showsGlow = showsGlow
		self.playsSound = playsSound
	}
}
