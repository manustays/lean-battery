import AppKit
import LeanBatteryCore

/// Builds `NSImage`s from `IconRenderer` at 1× and 2×; used by the menubar item and the notification pill.
enum BatteryIconImage {
	/// Image for `spec`, drawn with a white foreground when `isDark`.
	static func make(for spec: IconSpec, isDark: Bool) -> NSImage {
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
