import AppKit
import Observation
import LeanBatteryCore

/// The only code in the app that talks to the network (spec §13.3). Notify-only: it never downloads an update.
/// No timer and no background thread — a check happens when the popover opens or the user asks for one.
@MainActor
@Observable
final class UpdateService {
	/// What the popover and settings display.
	private(set) var status: UpdateStatus = .idle

	/// Whether checking is allowed at all. Turning it off cancels any in-flight request — off means no network access.
	var isEnabled: Bool {
		didSet {
			guard isEnabled != oldValue else { return }
			UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.updateCheckEnabled)
			if !isEnabled {
				task?.cancel()
				task = nil
			}
			status = UpdatePolicy.status(state: state, enabled: isEnabled, currentVersion: installedVersion, now: Date().timeIntervalSince1970)
		}
	}

	/// `CFBundleShortVersionString`, the version every comparison is made against.
	let installedVersion: String

	/// The command shown next to the Homebrew button.
	static let brewCommand = "brew upgrade --cask manustays/tools/leanbattery"

	@ObservationIgnored private var state: UpdateState
	@ObservationIgnored private var task: Task<Void, Never>?
	@ObservationIgnored private let session: URLSession

	/// Loads persisted state and derives the status to show before any network call.
	init() {
		installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
		isEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.updateCheckEnabled)
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = 10
		configuration.waitsForConnectivity = false
		session = URLSession(configuration: configuration)
		state = Self.loadState()
		status = UpdatePolicy.status(state: state, enabled: isEnabled, currentVersion: installedVersion, now: Date().timeIntervalSince1970)
	}

	/// Runs a check if policy allows one. `manual: true` skips the 24 h cooldown but not a rate limit.
	func check(manual: Bool) {
		let now = Date().timeIntervalSince1970
		guard UpdatePolicy.shouldCheck(manual: manual, enabled: isEnabled, inFlight: task != nil, state: state, now: now) else { return }
		status = .checking
		task = Task { [weak self] in
			guard let self else { return }
			let outcome = await Self.fetch(session: session, etag: state.etag, version: installedVersion)
			guard !Task.isCancelled, isEnabled else { return }   // a late result after opt-out is discarded
			task = nil
			state = UpdatePolicy.apply(outcome, to: state, now: Date().timeIntervalSince1970, currentVersion: installedVersion)
			save()
			status = UpdatePolicy.status(state: state, enabled: isEnabled, currentVersion: installedVersion, now: Date().timeIntervalSince1970)
		}
	}

	/// Hides the offered version until a newer one appears.
	func dismissCurrentOffer() {
		guard case .available(let version, _) = status else { return }
		state.dismissedVersion = version
		save()
		status = UpdatePolicy.status(state: state, enabled: isEnabled, currentVersion: installedVersion, now: Date().timeIntervalSince1970)
	}

	/// Opens the release page — only ever a validated project release URL.
	func openDownloadPage() {
		guard case .available(_, let url) = status, let validated = UpdatePolicy.releaseURL(url),
			let target = URL(string: validated) else { return }
		NSWorkspace.shared.open(target)
	}

	/// Puts the Homebrew upgrade command on the pasteboard.
	func copyBrewCommand() {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(Self.brewCommand, forType: .string)
	}

	// MARK: - Network

	/// One GET against the latest-release endpoint, mapped onto `UpdateOutcome`. Never throws.
	private static func fetch(session: URLSession, etag: String?, version: String) async -> UpdateOutcome {
		guard let url = URL(string: "https://api.github.com/repos/manustays/lean-battery/releases/latest") else {
			return .failed(reason: "bad endpoint")
		}
		var request = URLRequest(url: url)
		request.setValue("LeanBattery/\(version)", forHTTPHeaderField: "User-Agent")
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
		if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
		do {
			let (data, response) = try await session.data(for: request)
			guard let http = response as? HTTPURLResponse else { return .failed(reason: "no response") }
			switch http.statusCode {
			case 200:
				guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
					let tag = json["tag_name"] as? String, let page = json["html_url"] as? String else {
					return .failed(reason: "unreadable response")
				}
				return .ok(tag: tag, url: page, etag: http.value(forHTTPHeaderField: "ETag"))
			case 304:
				return .notModified
			case 404:
				return .noReleases
			case 403, 429:
				return .rateLimited(resetAt: rateLimitReset(from: http))
			default:
				return .failed(reason: "GitHub returned \(http.statusCode)")
			}
		} catch is CancellationError {
			return .failed(reason: "cancelled")
		} catch {
			return .failed(reason: error.localizedDescription)
		}
	}

	/// `Retry-After` (seconds) or `X-RateLimit-Reset` (unix seconds), whichever the response carries.
	private static func rateLimitReset(from response: HTTPURLResponse) -> Double? {
		if let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) {
			return Date().timeIntervalSince1970 + retry
		}
		return response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init)
	}

	// MARK: - Persistence

	/// Reads the stored state; absent numbers stay nil rather than becoming 0.
	private static func loadState() -> UpdateState {
		let defaults = UserDefaults.standard
		var state = UpdateState()
		state.lastAttempt = defaults.object(forKey: DefaultsKey.updateLastAttempt) as? Double
		state.lastSuccess = defaults.object(forKey: DefaultsKey.updateLastSuccess) as? Double
		state.rateLimitReset = defaults.object(forKey: DefaultsKey.updateRateLimitReset) as? Double
		state.etag = defaults.string(forKey: DefaultsKey.updateETag)
		state.cachedTag = defaults.string(forKey: DefaultsKey.updateCachedTag)
		state.cachedURL = defaults.string(forKey: DefaultsKey.updateCachedURL)
		state.dismissedVersion = defaults.string(forKey: DefaultsKey.updateDismissedVersion)
		return state
	}

	/// Writes the state back.
	private func save() {
		let defaults = UserDefaults.standard
		defaults.set(state.lastAttempt, forKey: DefaultsKey.updateLastAttempt)
		defaults.set(state.lastSuccess, forKey: DefaultsKey.updateLastSuccess)
		defaults.set(state.rateLimitReset, forKey: DefaultsKey.updateRateLimitReset)
		defaults.set(state.etag, forKey: DefaultsKey.updateETag)
		defaults.set(state.cachedTag, forKey: DefaultsKey.updateCachedTag)
		defaults.set(state.cachedURL, forKey: DefaultsKey.updateCachedURL)
		defaults.set(state.dismissedVersion, forKey: DefaultsKey.updateDismissedVersion)
	}
}
