import CoreGraphics
import CoreText
import Foundation

/// Draws the upright battery icon (spec §4.1) into a transparent bitmap.
public enum IconRenderer {
	/// Icon canvas in points.
	public static let size = CGSize(width: 11, height: 22)

	private static let cap = CGRect(x: 3.5, y: 0.4, width: 4.0, height: 1.6)
	private static let body = CGRect(x: 0.45, y: 2.2, width: 10.1, height: 19.4)
	private static let bodyStrokeWidth = 0.9
	private static let inner = CGRect(x: 1.35, y: 3.1, width: 8.3, height: 17.6)
	private static let badgeCenter = CGPoint(x: 8.9, y: 2.3)
	/// Fill opacities: soft enough that a solid glyph drawn on top stays readable.
	private static let foregroundFillAlpha = 0.28
	private static let colorFillAlpha = 0.6
	/// Core Text trait values for SF semibold compressed (raw values of NSFont.Weight.semibold / NSFont.Width.compressed).
	private static let numberWeightTrait = 0.3
	private static let numberWidthTrait = -0.3
	private static let plugScale = 1.3

	/// Renders `spec` at `scale` (1 or 2 for menubar use). `foregroundIsWhite` follows the menubar appearance.
	public static func render(_ spec: IconSpec, foregroundIsWhite: Bool, scale: CGFloat) -> CGImage? {
		let width = Int(size.width * scale)
		let height = Int(size.height * scale)
		guard
			let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
			let context = CGContext(
				data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
				space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			)
		else { return nil }
		// Top-left origin in points, matching the spec geometry.
		context.translateBy(x: 0, y: CGFloat(height))
		context.scaleBy(x: scale, y: -scale)
		draw(spec, foreground: foregroundIsWhite ? white : black, in: context)
		return context.makeImage()
	}

	/// Draws into a context whose user space is 11 × 22 pt with a top-left origin.
	static func draw(_ spec: IconSpec, foreground: CGColor, in context: CGContext) {
		context.setFillColor(foreground)
		context.addPath(roundedRect(cap, radius: 0.6))
		context.fillPath()

		context.setStrokeColor(foreground)
		context.setLineWidth(bodyStrokeWidth)
		context.addPath(roundedRect(body, radius: 2.6))
		context.strokePath()

		let fillHeight = inner.height * spec.fillFraction
		if fillHeight > 0 {
			let fillRect = CGRect(x: inner.minX, y: inner.maxY - fillHeight, width: inner.width, height: fillHeight)
			context.setFillColor(fillColor(for: spec.fill, foreground: foreground))
			context.addPath(roundedRect(fillRect, radius: min(1.7, fillHeight / 2)))
			context.fillPath()
		}

		// One solid color over the soft fill, so digits are never split at the fill line.
		drawGlyph(spec, color: foreground, in: context)

		if spec.showsHotBadge {
			context.saveGState()
			context.setBlendMode(.clear)
			context.fillEllipse(in: circle(badgeCenter, radius: 2.9))
			context.restoreGState()
			context.setFillColor(red)
			context.fillEllipse(in: circle(badgeCenter, radius: 2.1))
		}
	}

	/// Draws the number or plug glyph centered in the inner area.
	private static func drawGlyph(_ spec: IconSpec, color: CGColor, in context: CGContext) {
		context.setFillColor(color)
		switch spec.glyph {
		case .plug:
			let transform = CGAffineTransform(translationX: inner.midX, y: inner.midY).scaledBy(x: plugScale, y: plugScale)
			let parts: [(CGRect, CGFloat)] = [
				(CGRect(x: -1.55, y: -3.7, width: 0.85, height: 2.0), 0.3),
				(CGRect(x: 0.70, y: -3.7, width: 0.85, height: 2.0), 0.3),
				(CGRect(x: -2.2, y: -1.9, width: 4.4, height: 3.4), 1.1),
				(CGRect(x: -0.5, y: 1.3, width: 1.0, height: 2.4), 0.3),
			]
			for (rect, radius) in parts {
				context.addPath(roundedRect(rect, radius: radius, transform: transform))
			}
			context.fillPath()
		case .number(let value):
			let font = numberFont(size: CGFloat(spec.numberFontSize))
			let attributes: [NSAttributedString.Key: Any] = [
				NSAttributedString.Key(kCTFontAttributeName as String): font,
				NSAttributedString.Key(kCTKernAttributeName as String): -0.3,
				NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
			]
			let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(value), attributes: attributes))
			let width = CTLineGetTypographicBounds(line, nil, nil, nil)
			context.saveGState()
			// Undo the flipped CTM for text so glyphs are upright; center the cap height vertically.
			context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
			context.textPosition = CGPoint(x: inner.midX - width / 2, y: inner.midY + CTFontGetCapHeight(font) / 2)
			CTLineDraw(line, context)
			context.restoreGState()
		}
	}

	/// SF semibold compressed at `size`, built from Core Text traits so the core library needs no AppKit.
	private static func numberFont(size: CGFloat) -> CTFont {
		let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
		let traits: [CFString: Any] = [kCTFontWeightTrait: numberWeightTrait, kCTFontWidthTrait: numberWidthTrait]
		let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base), [kCTFontTraitsAttribute: traits] as CFDictionary)
		return CTFontCreateWithFontDescriptor(descriptor, size, nil)
	}

	/// Maps a fill role to its translucent fill color.
	private static func fillColor(for fill: IconSpec.Fill, foreground: CGColor) -> CGColor {
		switch fill {
		case .foreground: foreground.copy(alpha: foregroundFillAlpha) ?? foreground
		case .lowPower: CGColor(srgbRed: 1.0, green: 0.839, blue: 0.039, alpha: colorFillAlpha)
		case .charging: CGColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: colorFillAlpha)
		case .low: CGColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: colorFillAlpha)
		}
	}

	private static var white: CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) }
	private static var black: CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) }
	private static var red: CGColor { CGColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1) }

	/// Rounded rectangle path with the corner radius clamped to the rect size.
	private static func roundedRect(_ rect: CGRect, radius: CGFloat, transform: CGAffineTransform = .identity) -> CGPath {
		var transform = transform
		let clamped = min(radius, rect.width / 2, rect.height / 2)
		return CGPath(roundedRect: rect, cornerWidth: clamped, cornerHeight: clamped, transform: &transform)
	}

	/// Square rect bounding a circle.
	private static func circle(_ center: CGPoint, radius: CGFloat) -> CGRect {
		CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
	}
}
