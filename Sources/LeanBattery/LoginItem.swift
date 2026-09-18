import Foundation
import ServiceManagement

/// Launch at login (spec §5.5, §9): `SMAppService` first, a per-user LaunchAgent plist if registration is rejected.
@MainActor
enum LoginItem {
	/// True when registered, awaiting approval, or running from the LaunchAgent fallback.
	static var isEnabled: Bool {
		switch SMAppService.mainApp.status {
		case .enabled, .requiresApproval: true
		default: FileManager.default.fileExists(atPath: fallbackURL.path)
		}
	}

	/// Extra status line for the settings row, or nil when nothing needs saying.
	static var statusText: String? {
		switch SMAppService.mainApp.status {
		case .requiresApproval: "Approve LeanBattery in System Settings → General → Login Items."
		case .enabled: nil
		default: FileManager.default.fileExists(atPath: fallbackURL.path) ? "Using a LaunchAgent (login item registration unavailable)." : nil
		}
	}

	/// Turns launch at login on or off. Does nothing when already in that state (re-registering re-fires macOS's background-item notice). Returns an error message on failure.
	static func setEnabled(_ enabled: Bool) -> String? {
		guard enabled != isEnabled else { return nil }
		if enabled {
			do {
				try SMAppService.mainApp.register()
				return nil
			} catch {
				return writeFallbackAgent(after: error)
			}
		}
		try? FileManager.default.removeItem(at: fallbackURL)
		guard SMAppService.mainApp.status != .notRegistered else { return nil }
		do {
			try SMAppService.mainApp.unregister()
			return nil
		} catch {
			return "Couldn't turn off launch at login: \(error.localizedDescription)"
		}
	}

	/// `~/Library/LaunchAgents/<bundle id>.plist`.
	private static var fallbackURL: URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/LaunchAgents/\(Bundle.main.bundleIdentifier ?? "LeanBattery").plist")
	}

	/// Writes a RunAtLoad LaunchAgent for this executable; returns an error message if that also fails.
	private static func writeFallbackAgent(after registrationError: Error) -> String? {
		guard let label = Bundle.main.bundleIdentifier, let executable = Bundle.main.executableURL?.path else {
			return "Couldn't turn on launch at login: \(registrationError.localizedDescription)"
		}
		let plist: [String: Any] = ["Label": label, "ProgramArguments": [executable], "RunAtLoad": true]
		do {
			try FileManager.default.createDirectory(at: fallbackURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
			try data.write(to: fallbackURL, options: .atomic)
			return nil
		} catch {
			return "Couldn't turn on launch at login: \(error.localizedDescription)"
		}
	}
}
