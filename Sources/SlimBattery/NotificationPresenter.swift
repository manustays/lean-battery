import AppKit
import SlimBatteryCore

/// Turns a `NotificationEvent` into the pill, the glow, and the alert sound, and takes them away
/// after the user's duration (spec §6.3–§6.5). Nothing here runs between events.
@MainActor
final class NotificationPresenter {
	/// Notification preferences; read for the current duration on every show.
	private let settings: NotificationSettings
	/// Owns the screen-edge glow window.
	private let glow = GlowPresenter()
	/// Owns the floating pill panel; dismisses itself when the user clicks it.
	private lazy var pill = PillPresenter { [weak self] in self?.dismiss() }
	/// The pending dismissal timer, or nil when nothing is shown.
	private var timer: Timer?

	/// Keeps the settings so every event uses the current duration, and closes both windows if the displays change (spec §9).
	init(settings: NotificationSettings) {
		self.settings = settings
		// ponytail: lives for the app's lifetime, so this observer and its token are never removed.
		NotificationCenter.default.addObserver(
			forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
		) { [weak self] _ in
			guard let self else { return }
			MainActor.assumeIsolated { self.dismiss(animated: false) }
		}
	}

	/// Shows `event`: the pill always, the glow when the rule asks for it, the sound once.
	func show(_ event: NotificationEvent) {
		let icon = BatteryIconImage.make(for: IconSpec(state: event.state), isDark: true)
		// Only a below-rule is bad news, so only it tints the pill's border red — the same rule the glow follows.
		let isAlert: Bool
		if case .below = event.kind { isAlert = true } else { isAlert = false }
		pill.show(
			content: PillContent(event: event, adapterWatts: SystemPower.adapterWatts()),
			icon: icon,
			metrics: PillMetrics(style: settings.pillStyle),
			isAlert: isAlert)
		if event.showsGlow, let screen = PillPresenter.activeScreen() {
			glow.show(on: screen)
		} else {
			glow.hide()
		}
		if event.playsSound {
			NSSound.beep()
		}
		timer?.invalidate()
		let timer = Timer(timeInterval: TimeInterval(settings.duration), repeats: false) { [weak self] _ in
			guard let self else { return }
			MainActor.assumeIsolated { self.dismiss() }
		}
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
	}

	/// The sample low-battery notification behind the `Preview notification` button (spec §6.1).
	func preview() {
		show(NotificationEvent(
			kind: .below(threshold: 20),
			state: BatteryState(percent: 10, minutesRemaining: 38),
			showsGlow: true,
			playsSound: false))
	}

	/// Hides the pill and the glow and cancels the dismissal timer.
	func dismiss(animated: Bool = true) {
		timer?.invalidate()
		timer = nil
		pill.dismiss(animated: animated)
		glow.hide(animated: animated)
	}
}
