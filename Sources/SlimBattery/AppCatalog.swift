import AppKit
import SlimBatteryCore

/// Resolves powerlog identifiers to installed applications.
///
/// LaunchServices caches lookups internally (28 ms for the first seven ids, 0 ms afterwards),
/// so this holds no cache of its own.
@MainActor
enum AppCatalog {
	/// The app's URL when the id belongs to an installed application.
	private static func url(for id: String) -> URL? {
		NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
	}

	/// True when the id resolves to an installed `.app`.
	static func isApplication(_ id: String) -> Bool {
		url(for: id) != nil
	}

	/// The application's display name, or a name derived from the identifier.
	/// Many real top consumers (`sh.brew.sketchybar`, `com.apple.WindowServer`) resolve to no app.
	static func displayName(for id: String) -> String {
		guard let url = url(for: id) else { return EnergyName.fallbackDisplayName(for: id) }
		let name = FileManager.default.displayName(atPath: url.path)
		return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
	}

	/// A 16 pt icon, or nil for identifiers with no application behind them.
	static func icon(for id: String) -> NSImage? {
		guard let url = url(for: id) else { return nil }
		let icon = NSWorkspace.shared.icon(forFile: url.path)
		icon.size = NSSize(width: 16, height: 16)
		return icon
	}
}
