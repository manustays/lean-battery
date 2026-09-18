/// Everything the update checker persists between launches (spec §13.3). Times are unix seconds.
public struct UpdateState: Equatable, Sendable {
	public var lastAttempt: Double?
	public var lastSuccess: Double?
	public var rateLimitReset: Double?
	public var etag: String?
	public var cachedTag: String?
	public var cachedURL: String?
	public var dismissedVersion: String?

	public init() {}
}

/// What one HTTP attempt turned into. The app maps URLSession results onto this; the policy sees nothing else.
public enum UpdateOutcome: Equatable, Sendable {
	case ok(tag: String, url: String, etag: String?)
	case notModified
	case noReleases
	case rateLimited(resetAt: Double?)
	case failed(reason: String)
}

/// What the UI shows (spec §13.3).
public enum UpdateStatus: Equatable, Sendable {
	case disabled
	case idle
	case checking
	case current(String)
	case available(version: String, url: String)
	case noReleases
	case failed(reason: String)
}

/// Every update decision, pure: when to check, what a result means, and what to display.
public enum UpdatePolicy {
	/// Minimum gap between automatic checks.
	public static let cooldown: Double = 24 * 60 * 60
	/// Only release pages under this prefix are ever opened.
	public static let releasePrefix = "https://github.com/manustays/lean-battery/releases/"

	/// Whether a check may run now. Automatic checks wait out the cooldown; manual checks skip it.
	/// A rate-limit reset in the future blocks both. A last attempt in the future (clock moved back) is eligible once.
	public static func shouldCheck(manual: Bool, enabled: Bool, inFlight: Bool, state: UpdateState, now: Double) -> Bool {
		guard enabled, !inFlight else { return false }
		if let reset = state.rateLimitReset, reset > now { return false }
		if manual { return true }
		guard let lastAttempt = state.lastAttempt else { return true }
		if lastAttempt > now { return true }
		return now - lastAttempt >= cooldown
	}

	/// Folds one attempt's outcome into the persisted state. Always stamps `lastAttempt`.
	public static func apply(_ outcome: UpdateOutcome, to state: UpdateState, now: Double, currentVersion: String) -> UpdateState {
		var next = state
		next.lastAttempt = now
		switch outcome {
		case .ok(let tag, let url, let etag):
			next.lastSuccess = now
			next.rateLimitReset = nil
			next.cachedTag = tag
			next.cachedURL = url
			next.etag = etag ?? state.etag
			// A dismissal only ever hides the version it was made for.
			if let dismissed = next.dismissedVersion.flatMap(SemanticVersion.init),
				let offered = SemanticVersion(tag), offered > dismissed {
				next.dismissedVersion = nil
			}
		case .notModified:
			next.lastSuccess = now
			next.rateLimitReset = nil
		case .noReleases:
			next.lastSuccess = now
			next.rateLimitReset = nil
			next.cachedTag = nil
			next.cachedURL = nil
			next.etag = nil
		case .rateLimited(let resetAt):
			next.rateLimitReset = resetAt ?? now + cooldown / 24
		case .failed:
			break
		}
		return next
	}

	/// What to display for a stored state. Never offers a downgrade, a prerelease, or an off-site URL.
	public static func status(state: UpdateState, enabled: Bool, currentVersion: String) -> UpdateStatus {
		guard enabled else { return .disabled }
		if let reset = state.rateLimitReset, reset > (state.lastAttempt ?? 0) { return .failed(reason: "rate limited") }
		guard state.lastSuccess != nil else {
			return state.lastAttempt == nil ? .idle : .failed(reason: "couldn't reach GitHub")
		}
		guard let tag = state.cachedTag else { return .noReleases }
		guard let offered = SemanticVersion(tag), let url = state.cachedURL.flatMap(releaseURL) else {
			return .current(currentVersion)
		}
		guard let installed = SemanticVersion(currentVersion), offered > installed else { return .current(currentVersion) }
		if let dismissed = state.dismissedVersion.flatMap(SemanticVersion.init), !(offered > dismissed) {
			return .current(currentVersion)
		}
		return .available(version: "\(offered.major).\(offered.minor).\(offered.patch)", url: url)
	}

	/// The URL if it is a page under this project's releases, otherwise nil.
	public static func releaseURL(_ raw: String) -> String? {
		raw.hasPrefix(releasePrefix) ? raw : nil
	}
}
