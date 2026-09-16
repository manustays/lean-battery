import AppKit
import SwiftUI

/// Shows the SwiftUI popover under the status item and ties the model's refresh timer to popover visibility.
@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
	private let popover = NSPopover()
	private let model: PopoverModel

	/// Creates a transient popover hosting `PopoverView`.
	init(model: PopoverModel) {
		self.model = model
		super.init()
		let hosting = NSHostingController(rootView: PopoverView(model: model))
		hosting.sizingOptions = [.preferredContentSize]
		popover.contentViewController = hosting
		popover.behavior = .transient
		popover.animates = false
		popover.delegate = self
	}

	/// Opens the popover below `button`, or closes it if already shown.
	func toggle(relativeTo button: NSStatusBarButton) {
		if popover.isShown {
			popover.performClose(nil)
			return
		}
		model.start()
		NSApplication.shared.activate()
		popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
	}

	/// Stops the refresh timer once the popover is gone.
	func popoverDidClose(_ notification: Notification) {
		model.stop()
	}
}
