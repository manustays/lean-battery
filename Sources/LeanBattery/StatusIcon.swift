import AppKit
import LeanBatteryCore

/// Owns the menubar status item; redraws only when the visible spec or menubar appearance changes. A click calls `onClick`.
@MainActor
final class StatusIcon: NSObject {
	private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
	private let onClick: (NSStatusBarButton) -> Void
	private var state: BatteryState?
	private var drawnSpec: IconSpec?
	private var drawnDark: Bool?
	private var appearanceObservation: NSKeyValueObservation?

	/// Creates the status item, showing a "—" placeholder until real battery data arrives.
	init(onClick: @escaping (NSStatusBarButton) -> Void) {
		self.onClick = onClick
		super.init()
		statusItem.button?.title = "—"
		statusItem.button?.setAccessibilityLabel("Battery status unavailable")
		statusItem.button?.target = self
		statusItem.button?.action = #selector(buttonClicked(_:))
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

	/// Forwards status item clicks.
	@objc private func buttonClicked(_ sender: NSStatusBarButton) {
		onClick(sender)
	}

	/// Redraws the button image when spec or appearance differs from what is on screen.
	private func redrawIfNeeded() {
		guard let state, let button = statusItem.button else { return }
		let spec = IconSpec(state: state)
		let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
		guard spec != drawnSpec || isDark != drawnDark else { return }
		drawnSpec = spec
		drawnDark = isDark
		button.image = BatteryIconImage.make(for: spec, isDark: isDark)
		button.title = ""
		button.imagePosition = .imageOnly
	}
}
