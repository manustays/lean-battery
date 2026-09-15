import AppKit
import SlimBatteryCore

/// Owns the menubar status item; redraws only when the visible spec or menubar appearance changes.
@MainActor
final class StatusIcon {
	private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
	private var state: BatteryState?
	private var drawnSpec: IconSpec?
	private var drawnDark: Bool?
	private var appearanceObservation: NSKeyValueObservation?

	/// Creates the status item with a temporary Quit menu, showing a "—" placeholder until real battery data arrives.
	init() {
		// ponytail: Quit-only menu until the popover replaces it (Plan 2).
		let menu = NSMenu()
		menu.addItem(withTitle: "Quit SlimBattery", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		statusItem.menu = menu
		statusItem.button?.title = "—"
		statusItem.button?.setAccessibilityLabel("Battery status unavailable")
		appearanceObservation = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
			guard let self else { return }
			MainActor.assumeIsolated { self.redrawIfNeeded() }
		}
	}

	/// Stores the latest state, updates the VoiceOver label, and redraws if the icon would change.
	func update(_ state: BatteryState) {
		self.state = state
		statusItem.button?.setAccessibilityLabel(state.accessibilityDescription)
		redrawIfNeeded()
	}

	/// Redraws the button image when spec or appearance differs from what is on screen.
	private func redrawIfNeeded() {
		guard let state, let button = statusItem.button else { return }
		let spec = IconSpec(state: state)
		let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
		guard spec != drawnSpec || isDark != drawnDark else { return }
		drawnSpec = spec
		drawnDark = isDark
		button.image = Self.image(for: spec, isDark: isDark)
		button.title = ""
		button.imagePosition = .imageOnly
	}

	/// Builds an NSImage with 1× and 2× bitmap representations.
	private static func image(for spec: IconSpec, isDark: Bool) -> NSImage {
		let image = NSImage(size: IconRenderer.size)
		for scale in [1.0, 2.0] {
			guard let cgImage = IconRenderer.render(spec, foregroundIsWhite: isDark, scale: scale) else { continue }
			let representation = NSBitmapImageRep(cgImage: cgImage)
			representation.size = IconRenderer.size
			image.addRepresentation(representation)
		}
		return image
	}
}
