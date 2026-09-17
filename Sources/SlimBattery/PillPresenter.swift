import AppKit
import SwiftUI
import SlimBatteryCore

/// Owns the floating pill panel (spec §6.3): created on demand, animated in and out, destroyed after dismissal.
/// The floating styles slide down from under the menubar; the notch style reveals outward from the display's notch.
@MainActor
final class PillPresenter {
	/// Slide distance of the entrance and exit animation, for the floating styles.
	private static let slide: CGFloat = 14
	/// Duration of the entrance and exit animation, for the floating styles.
	private static let animationDuration = 0.25
	/// Duration of the notch style's hide, a little quicker than the reveal.
	private static let concealDuration = 0.22

	/// The currently shown panel, or nil when no pill is on screen.
	private var panel: NSPanel?
	/// The panel's SwiftUI content view, kept so `show` can swap its `rootView` in place.
	private var hosting: NSHostingView<PillView>?
	/// Geometry of the pill currently on screen, so `dismiss` can reverse the matching animation.
	private var metrics: PillMetrics?
	/// What the visible pill is showing, so it can be rebuilt with a different reveal state.
	private var shown: (content: PillContent, icon: NSImage, collapsed: CGSize, isAlert: Bool)?
	/// Called when the user clicks the pill.
	private let onDismiss: () -> Void

	/// `onDismiss` runs when the user clicks the pill.
	init(onDismiss: @escaping () -> Void) {
		self.onDismiss = onDismiss
	}

	/// Shows `content` in the style `metrics` describes; a visible pill is replaced in place,
	/// without replaying the entrance (spec §6.3).
	func show(content: PillContent, icon: NSImage, style: PillStyle, isAlert: Bool) {
		guard let screen = Self.activeScreen() else { return }
		let metrics = Self.metrics(for: style, on: screen)
		let collapsed = Self.collapsedSize(on: screen, metrics: metrics)
		self.metrics = metrics
		shown = (content, icon, collapsed, isAlert)
		guard let revealed = makeView(isRevealed: true) else { return }
		if let panel, let hosting {
			// Already revealed: swap the contents and resize under it, no second entrance.
			hosting.rootView = revealed
			panel.setFrame(Self.frame(for: hosting, on: screen, metrics: metrics), display: true)
			return
		}
		// The notch style starts masked down to the cutout and grows once it is on screen; the floating
		// styles have no mask and animate their window instead.
		let hosting = NSHostingView(rootView: metrics.hugsTopEdge ? (makeView(isRevealed: false) ?? revealed) : revealed)
		let frame = Self.frame(for: hosting, on: screen, metrics: metrics)
		let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
		panel.isFloatingPanel = true
		panel.becomesKeyOnlyIfNeeded = true
		// Above GlowPresenter's .screenSaver window: the glow's red border drawing across the pill's top
		// edge would give away that the notch style is a separate window.
		panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
		panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
		panel.backgroundColor = .clear
		panel.isOpaque = false
		panel.hasShadow = false
		panel.hidesOnDeactivate = false
		// NSPanel already defaults isReleasedWhenClosed to false (unlike NSWindow); set it explicitly so
		// this presenter and GlowPresenter state the same intent rather than relying on a type default.
		panel.isReleasedWhenClosed = false
		// ultraThinMaterial bridges to an NSVisualEffectView that follows the host NSAppearance, not the
		// SwiftUI .environment(\.colorScheme, .dark) PillView sets — pin it so the white title stays legible.
		panel.appearance = NSAppearance(named: .darkAqua)
		// The system's default order-front/close fade would compound with the hand-rolled animations below.
		panel.animationBehavior = .none
		panel.contentView = hosting
		self.panel = panel
		self.hosting = hosting
		guard !metrics.hugsTopEdge else {
			// Full size and fully opaque from the start: the mask inside does the growing.
			panel.setFrame(frame, display: false)
			panel.orderFrontRegardless()
			// One turn of the run loop so SwiftUI sees the collapsed state before it animates out of it.
			DispatchQueue.main.async { [weak self] in
				guard let self, let hosting = self.hosting, let view = self.makeView(isRevealed: true) else { return }
				hosting.rootView = view
			}
			return
		}
		panel.alphaValue = 0
		panel.setFrame(Self.entranceFrame(for: frame), display: false)
		panel.orderFrontRegardless()
		NSAnimationContext.runAnimationGroup { context in
			context.duration = Self.animationDuration
			context.timingFunction = CAMediaTimingFunction(name: .easeOut)
			panel.animator().alphaValue = 1
			panel.animator().setFrame(frame, display: true)
		}
	}

	/// Rebuilds the visible pill at the given reveal state, or nil once nothing is showing.
	private func makeView(isRevealed: Bool) -> PillView? {
		guard let shown, let metrics else { return nil }
		return PillView(
			icon: shown.icon,
			content: shown.content,
			metrics: metrics,
			isAlert: shown.isAlert,
			collapsedSize: shown.collapsed,
			isRevealed: isRevealed) { [weak self] in
				self?.onDismiss()
			}
	}

	/// Reverses the entrance — a slide back up, or a collapse into the notch — then closes and releases the panel.
	func dismiss(animated: Bool = true) {
		guard let panel else { return }
		let hosting = self.hosting
		self.panel = nil
		guard animated else {
			self.hosting = nil
			shown = nil
			metrics = nil
			panel.close()
			return
		}
		self.hosting = nil
		if metrics?.hugsTopEdge == true, let hosting, let collapsed = makeView(isRevealed: false) {
			// Shrink back into the cutout under the same spring, then close once it has played out.
			hosting.rootView = collapsed
			self.shown = nil
			self.metrics = nil
			DispatchQueue.main.asyncAfter(deadline: .now() + Self.concealDuration) {
				panel.close()
			}
			return
		}
		self.shown = nil
		self.metrics = nil
		var exitFrame = panel.frame
		exitFrame.origin.y += Self.slide
		NSAnimationContext.runAnimationGroup { context in
			context.duration = Self.animationDuration
			context.timingFunction = CAMediaTimingFunction(name: .easeIn)
			panel.animator().alphaValue = 0
			panel.animator().setFrame(exitFrame, display: true)
		} completionHandler: {
			// The completion handler is not statically MainActor-isolated; this class only ever runs on the main actor.
			MainActor.assumeIsolated { panel.close() }
		}
	}

	/// The notch's own footprint on this screen — what the notch style grows out of and shrinks back into.
	private static func collapsedSize(on screen: NSScreen, metrics: PillMetrics) -> CGSize {
		guard metrics.hugsTopEdge else { return .zero }
		return CGSize(width: notchWidth(on: screen), height: max(screen.safeAreaInsets.top, 6))
	}

	/// The screen under the mouse pointer — the spec's stand-in for "the active screen" (§6.3).
	static func activeScreen() -> NSScreen? {
		let location = NSEvent.mouseLocation
		return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
	}

	/// Panel frame: fitted width, centered, body top either just under the menubar or flush to the
	/// screen's top edge for the notch style (spec §6.3).
	private static func frame(for hosting: NSView, on screen: NSScreen, metrics: PillMetrics) -> NSRect {
		let inset = PillView.shadowInset
		let width = hosting.fittingSize.width
		let height = metrics.totalHeight + inset * 2
		let bodyTop: CGFloat
		if metrics.hugsTopEdge {
			// Start at the very top: the strip either side of the notch is what makes the body read as
			// the notch itself having grown rather than a slab hanging beneath it.
			bodyTop = screen.frame.maxY
		} else {
			// The menubar/notch band: safe area on a notched display, otherwise the menubar or status bar height.
			let topInset = max(
				screen.safeAreaInsets.top,
				screen.frame.maxY - screen.visibleFrame.maxY,
				NSStatusBar.system.thickness)
			bodyTop = screen.frame.maxY - topInset - metrics.topGap
		}
		return NSRect(
			x: (screen.frame.midX - width / 2).rounded(),
			y: (bodyTop - metrics.totalHeight - inset).rounded(),
			width: width,
			height: height)
	}

	/// Where the floating styles' entrance starts and their exit ends: 14 pt higher than they settle.
	/// The notch style never moves its window — it grows under a mask instead.
	private static func entranceFrame(for frame: NSRect) -> NSRect {
		frame.offsetBy(dx: 0, dy: Self.slide)
	}

	/// Geometry for `style`, measured against this screen's notch when the style needs it.
	private static func metrics(for style: PillStyle, on screen: NSScreen) -> PillMetrics {
		PillMetrics(style: style, notchWidth: notchWidth(on: screen), notchHeight: screen.safeAreaInsets.top)
	}

	/// Width of the display's physical notch, or a stub of the same order on a display without one.
	private static func notchWidth(on screen: NSScreen) -> CGFloat {
		guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
			return PillMetrics.notchStubWidth
		}
		let width = screen.frame.width - left.width - right.width
		return width > 0 ? width : PillMetrics.notchStubWidth
	}
}
