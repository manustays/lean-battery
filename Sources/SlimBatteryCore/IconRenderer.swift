import CoreGraphics
import CoreText
import Foundation

/// Draws the upright battery icon (spec §4.1) into a transparent bitmap.
public enum IconRenderer {
	/// Icon canvas in points.
	public static let size = CGSize(width: 11, height: 22)

	private static let cap = CGRect(x: 3.5, y: 0.6, width: 4.0, height: 1.9)
	private static let body = CGRect(x: 0.6, y: 2.5, width: 9.8, height: 19.0)
	private static let inner = CGRect(x: 1.9, y: 3.8, width: 7.2, height: 16.4)
	private static let centerX = 5.5
	private static let innerMidY = 12.0
	private static let badgeCenter = CGPoint(x: 8.9, y: 2.3)

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
		context.setLineWidth(1.1)
		context.addPath(roundedRect(body, radius: 2.6))
		context.strokePath()

		let fillHeight = inner.height * spec.fillFraction
		let fillRect = CGRect(x: inner.minX, y: inner.maxY - fillHeight, width: inner.width, height: fillHeight)
		let fillColor = color(for: spec.fill, foreground: foreground)
		if fillHeight > 0 {
			context.setFillColor(fillColor)
			context.addPath(roundedRect(fillRect, radius: min(1.4, fillHeight / 2)))
			context.fillPath()
		}

		// Glyph in foreground everywhere, then knocked out (or blackened) where it overlaps the fill.
		drawGlyph(spec, color: foreground, in: context)
		if fillHeight > 0 {
			context.saveGState()
			context.clip(to: fillRect)
			if spec.fill == .foreground {
				context.setBlendMode(.clear)
			}
			drawGlyph(spec, color: black, in: context)
			context.restoreGState()
		}

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
			let transform = CGAffineTransform(translationX: centerX, y: innerMidY).scaledBy(x: 1.15, y: 1.15)
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
			let fontSize = CGFloat(spec.numberFontSize)
			let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil)
			let attributes: [NSAttributedString.Key: Any] = [
				NSAttributedString.Key(kCTFontAttributeName as String): font as Any,
				NSAttributedString.Key(kCTKernAttributeName as String): -0.25,
				NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
			]
			let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(value), attributes: attributes))
			let width = CTLineGetTypographicBounds(line, nil, nil, nil)
			context.saveGState()
			// Undo the flipped CTM for text so glyphs are upright.
			context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
			context.textPosition = CGPoint(x: centerX - width / 2, y: innerMidY + 0.36 * fontSize)
			CTLineDraw(line, context)
			context.restoreGState()
		}
	}

	/// Maps a fill role to a concrete color.
	private static func color(for fill: IconSpec.Fill, foreground: CGColor) -> CGColor {
		switch fill {
		case .foreground: foreground
		case .lowPower: CGColor(srgbRed: 1.0, green: 0.839, blue: 0.039, alpha: 1)
		case .charging: CGColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1)
		case .low: red
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
