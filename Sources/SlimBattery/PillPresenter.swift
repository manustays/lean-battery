import AppKit
import SwiftUI
import SlimBatteryCore

/// Owns the floating pill panel (spec §6.3): created on demand, animated in and out, destroyed after dismissal.
@MainActor
final class PillPresenter {
	/// Slide distance of the entrance and exit animation.
	private static let slide: CGFloat = 14
	/// Duration of the entrance and exit animation.
	private static let animationDuration = 0.25
	/// Gap between the menubar and the top of the capsule.
	private static let topGap: CGFloat = 8

	/// The currently shown panel, or nil when no pill is on screen.
	private var panel: NSPanel?
	/// The panel's SwiftUI content view, kept so `show` can swap its `rootView` in place.
	private var hosting: NSHostingView<PillView>?
	/// Called when the user clicks the pill.
	private let onDismiss: () -> Void

	/// `onDismiss` runs when the user clicks the pill.
	init(onDismiss: @escaping () -> Void) {
		self.onDismiss = onDismiss
	}

	/// Shows `content`; a visible pill is replaced in place, without replaying the entrance (spec §6.3).
	func show(content: PillContent, icon: NSImage) {
		guard let screen = Self.activeScreen() else { return }
		let view = PillView(icon: icon, content: content) { [weak self] in self?.onDismiss() }
		if let panel, let hosting {
			hosting.rootView = view
			panel.setFrame(Self.frame(for: hosting, on: screen), display: true)
			return
		}
		let hosting = NSHostingView(rootView: view)
		let frame = Self.frame(for: hosting, on: screen)
		let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
		panel.isFloatingPanel = true
		panel.becomesKeyOnlyIfNeeded = true
		panel.level = .statusBar
		panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
		panel.backgroundColor = .clear
		panel.isOpaque = false
		panel.hasShadow = false
		panel.hidesOnDeactivate = false
		panel.contentView = hosting
		panel.alphaValue = 0
		// Start 14 pt higher and fall into place.
		panel.setFrameOrigin(CGPoint(x: frame.origin.x, y: frame.origin.y + Self.slide))
		panel.orderFrontRegardless()
		self.panel = panel
		self.hosting = hosting
		NSAnimationContext.runAnimationGroup { context in
			context.duration = Self.animationDuration
			context.timingFunction = CAMediaTimingFunction(name: .easeOut)
			panel.animator().alphaValue = 1
			panel.animator().setFrame(frame, display: true)
		}
	}

	/// Slides the pill back up, fades it out, then closes and releases the panel.
	func dismiss(animated: Bool = true) {
		guard let panel else { return }
		self.panel = nil
		hosting = nil
		guard animated else {
			panel.close()
			return
		}
		var frame = panel.frame
		frame.origin.y += Self.slide
		NSAnimationContext.runAnimationGroup { context in
			context.duration = Self.animationDuration
			context.timingFunction = CAMediaTimingFunction(name: .easeIn)
			panel.animator().alphaValue = 0
			panel.animator().setFrame(frame, display: true)
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

	/// Panel frame: fitted width, centered, capsule top just under the menubar (spec §6.3).
	private static func frame(for hosting: NSView, on screen: NSScreen) -> NSRect {
		let inset = PillView.shadowInset
		let width = hosting.fittingSize.width
		let height = PillView.height + inset * 2
		// The menubar/notch band: safe area on a notched display, otherwise the menubar or status bar height.
		let topInset = max(
			screen.safeAreaInsets.top,
			screen.frame.maxY - screen.visibleFrame.maxY,
			NSStatusBar.system.thickness)
		let capsuleTop = screen.frame.maxY - topInset - topGap
		return NSRect(
			x: (screen.frame.midX - width / 2).rounded(),
			y: (capsuleTop - PillView.height - inset).rounded(),
			width: width,
			height: height)
	}
}
