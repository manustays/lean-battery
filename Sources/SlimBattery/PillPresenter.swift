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
	/// Duration of the notch style's reveal.
	private static let revealDuration = 0.28
	/// Duration of the notch style's hide, a little quicker than the reveal.
	private static let concealDuration = 0.22

	/// The currently shown panel, or nil when no pill is on screen.
	private var panel: NSPanel?
	/// The panel's SwiftUI content view, kept so `show` can swap its `rootView` in place.
	private var hosting: NSHostingView<PillView>?
	/// Geometry of the pill currently on screen, so `dismiss` can reverse the matching animation.
	private var metrics: PillMetrics?
	/// Called when the user clicks the pill.
	private let onDismiss: () -> Void

	/// `onDismiss` runs when the user clicks the pill.
	init(onDismiss: @escaping () -> Void) {
		self.onDismiss = onDismiss
	}

	/// Shows `content` in the style `metrics` describes; a visible pill is replaced in place,
	/// without replaying the entrance (spec §6.3).
	func show(content: PillContent, icon: NSImage, metrics: PillMetrics, isAlert: Bool) {
		guard let screen = Self.activeScreen() else { return }
		let view = PillView(icon: icon, content: content, metrics: metrics, isAlert: isAlert) { [weak self] in
			self?.onDismiss()
		}
		if let panel, let hosting {
			hosting.rootView = view
			self.metrics = metrics
			panel.setFrame(Self.frame(for: hosting, on: screen, metrics: metrics), display: true)
			return
		}
		let hosting = NSHostingView(rootView: view)
		let frame = Self.frame(for: hosting, on: screen, metrics: metrics)
		let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
		panel.isFloatingPanel = true
		panel.becomesKeyOnlyIfNeeded = true
		panel.level = .statusBar
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
		panel.alphaValue = 0
		panel.setFrame(Self.entranceFrame(for: frame, on: screen, metrics: metrics), display: false)
		panel.orderFrontRegardless()
		self.panel = panel
		self.hosting = hosting
		self.metrics = metrics
		NSAnimationContext.runAnimationGroup { context in
			context.duration = metrics.hugsTopEdge ? Self.revealDuration : Self.animationDuration
			context.timingFunction = CAMediaTimingFunction(name: .easeOut)
			panel.animator().alphaValue = 1
			panel.animator().setFrame(frame, display: true)
		}
	}

	/// Reverses the entrance — a slide back up, or a collapse into the notch — then closes and releases the panel.
	func dismiss(animated: Bool = true) {
		guard let panel else { return }
		let metrics = self.metrics
		self.panel = nil
		hosting = nil
		self.metrics = nil
		guard animated else {
			panel.close()
			return
		}
		let hugsTopEdge = metrics?.hugsTopEdge ?? false
		let screen = Self.activeScreen()
		let exitFrame: NSRect
		if hugsTopEdge, let metrics, let screen {
			exitFrame = Self.entranceFrame(for: panel.frame, on: screen, metrics: metrics)
		} else {
			var frame = panel.frame
			frame.origin.y += Self.slide
			exitFrame = frame
		}
		NSAnimationContext.runAnimationGroup { context in
			context.duration = hugsTopEdge ? Self.concealDuration : Self.animationDuration
			context.timingFunction = CAMediaTimingFunction(name: .easeIn)
			panel.animator().alphaValue = 0
			panel.animator().setFrame(exitFrame, display: true)
		} completionHandler: {
			// The completion handler is not statically MainActor-isolated; this class only ever runs on the main actor.
			MainActor.assumeIsolated { panel.close() }
		}
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
		let height = metrics.height + inset * 2
		let bodyTop: CGFloat
		if metrics.hugsTopEdge {
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
			y: (bodyTop - metrics.height - inset).rounded(),
			width: width,
			height: height)
	}

	/// Where the entrance animation starts and the exit animation ends: 14 pt higher for the floating
	/// styles, or collapsed to the notch's own footprint for the notch style.
	private static func entranceFrame(for frame: NSRect, on screen: NSScreen, metrics: PillMetrics) -> NSRect {
		guard metrics.hugsTopEdge else {
			return frame.offsetBy(dx: 0, dy: Self.slide)
		}
		let inset = PillView.shadowInset
		let width = notchWidth(on: screen) + inset * 2
		let bodyHeight = max(screen.safeAreaInsets.top, 24)
		return NSRect(
			x: (screen.frame.midX - width / 2).rounded(),
			y: (screen.frame.maxY - bodyHeight - inset).rounded(),
			width: width,
			height: bodyHeight + inset * 2)
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
