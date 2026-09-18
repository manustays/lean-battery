import AppKit
import QuartzCore

/// Owns the screen-edge glow window (spec §6.4): a click-through border that pulses while a below-rule pill is up.
@MainActor
final class GlowPresenter {
	/// The color of the glow border and bloom: alert red (sRGB 1.0, 0.271, 0.227).
	private static let color = CGColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1)
	/// Width of the border in points.
	private static let borderWidth: CGFloat = 3
	/// Radius of the inward bloom shadow in points.
	private static let bloomRadius: CGFloat = 16
	/// Opacity of the bloom shadow.
	private static let bloomOpacity: Float = 0.55
	/// ponytail: one radius for all four corners. The spec accepts square bottom corners on a built-in display.
	private static let cornerRadius: CGFloat = 10
	/// Duration of the pulse animation in seconds.
	private static let pulseDuration = 0.8
	/// Duration of the fade-out animation in seconds.
	private static let fadeOutDuration = 0.4

	/// The currently shown glow window, or nil when no glow is on screen.
	private var window: NSWindow?

	/// Shows the glow filling `screen`; an existing glow is replaced immediately.
	func show(on screen: NSScreen) {
		hide(animated: false)
		let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
		window.level = .screenSaver
		window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
		window.backgroundColor = .clear
		window.isOpaque = false
		window.hasShadow = false
		window.ignoresMouseEvents = true
		// The system's default order-front/close fade would compound with the hand-rolled fade below.
		window.animationBehavior = .none
		// NSWindow (unlike NSPanel) defaults isReleasedWhenClosed to true: AppKit would release the
		// object on close() on top of ARC's own release from `self.window = nil` in hide(), an over-release.
		window.isReleasedWhenClosed = false
		let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
		// Assign the custom layer before wantsLayer so the view is layer-hosting (we own the layer),
		// not layer-backed (AppKit owns it and may reset it).
		view.layer = Self.glowLayer(size: screen.frame.size)
		view.wantsLayer = true
		window.contentView = view
		window.setFrame(screen.frame, display: true)
		window.orderFrontRegardless()
		self.window = window
	}

	/// Fades the glow out, then closes and releases the window.
	func hide(animated: Bool = true) {
		guard let window else { return }
		self.window = nil
		guard animated else {
			window.close()
			return
		}
		NSAnimationContext.runAnimationGroup { context in
			context.duration = Self.fadeOutDuration
			window.animator().alphaValue = 0
		} completionHandler: {
			// The completion handler is not statically MainActor-isolated; this class only ever runs on the main actor.
			MainActor.assumeIsolated { window.close() }
		}
	}

	/// Border plus an inward bloom, pulsing on the window server so the app does no per-frame work.
	private static func glowLayer(size: CGSize) -> CALayer {
		let bounds = CGRect(origin: .zero, size: size)
		let layer = CALayer()
		layer.frame = bounds
		layer.borderColor = color
		layer.borderWidth = borderWidth
		layer.cornerRadius = cornerRadius
		layer.masksToBounds = true
		layer.shadowColor = color
		layer.shadowOpacity = bloomOpacity
		layer.shadowRadius = bloomRadius
		layer.shadowOffset = .zero
		// Inner shadow: shadow the area *outside* the rounded rect (a reversed subpath punches the hole),
		// then clip to bounds so only the inward bloom is visible.
		let cutout = NSBezierPath(rect: bounds.insetBy(dx: -bloomRadius * 2, dy: -bloomRadius * 2))
		cutout.append(NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).reversed)
		layer.shadowPath = cutout.cgPath
		let pulse = CABasicAnimation(keyPath: "opacity")
		pulse.fromValue = 0.45
		pulse.toValue = 1.0
		pulse.duration = pulseDuration
		pulse.autoreverses = true
		pulse.repeatCount = .infinity
		layer.add(pulse, forKey: "pulse")
		return layer
	}
}
