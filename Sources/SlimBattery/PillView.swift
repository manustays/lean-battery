import SwiftUI
import SlimBatteryCore

/// The floating pill's contents (spec §6.3): battery icon, title, detail. Its geometry comes from `PillMetrics`,
/// so the size styles and the notch style differ only in the numbers handed to it.
struct PillView: View {
	/// Transparent margin around the body so the drop shadow is not clipped by the window.
	static let shadowInset: CGFloat = 20
	/// Border tint for a low-battery alert, matching the screen-edge glow.
	private static let alertBorder = Color(.sRGB, red: 1.0, green: 0.271, blue: 0.227, opacity: 0.55)
	/// Border tint for every other event.
	private static let normalBorder = Color.white.opacity(0.14)

	/// The battery glyph shown at the body's leading edge.
	let icon: NSImage
	/// The title and detail text to display.
	let content: PillContent
	/// Geometry for the user's chosen style.
	let metrics: PillMetrics
	/// True for a low-battery rule, which tints the border red.
	let isAlert: Bool
	/// Called when the user taps the body.
	let onDismiss: () -> Void

	var body: some View {
		HStack(spacing: metrics.contentSpacing) {
			Image(nsImage: icon)
				.resizable()
				.frame(width: metrics.iconWidth, height: metrics.iconHeight)
			VStack(alignment: .center, spacing: 1) {
				Text(content.title)
					.font(.system(size: metrics.titleFontSize, weight: .semibold))
					.foregroundStyle(.white)
				Text(content.detail)
					.font(.system(size: metrics.detailFontSize))
					.foregroundStyle(.white.opacity(0.65))
			}
			.lineLimit(1)
			.multilineTextAlignment(.center)
		}
		.padding(.horizontal, metrics.horizontalPadding)
		// The clamp is the layout: short text grows to the minimum, long text stops at the maximum and truncates.
		.frame(
			minWidth: metrics.minimumWidth, maxWidth: metrics.maximumWidth,
			minHeight: metrics.height, maxHeight: metrics.height)
		// The notch style draws further up, filling the strip either side of the physical cutout; the
		// content stays in the band below it, which is the only part with pixels behind it.
		.padding(.top, metrics.topExtension)
		.background(background, in: shape)
		.overlay(shape.strokeBorder(borderColor, lineWidth: 1))
		.shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
		.environment(\.colorScheme, .dark)
		.contentShape(shape)
		.onTapGesture(perform: onDismiss)
		.padding(Self.shadowInset)
	}

	/// A low-battery alert tints the border red — except in the notch style, where a coloured outline
	/// breaks the illusion that the body is part of the bezel.
	private var borderColor: Color {
		isAlert && !metrics.hugsTopEdge ? Self.alertBorder : Self.normalBorder
	}

	/// The notch style is opaque black so it reads as an extension of the display's own bezel;
	/// the floating styles keep the translucent material.
	private var background: AnyShapeStyle {
		metrics.hugsTopEdge ? AnyShapeStyle(Color.black) : AnyShapeStyle(.ultraThinMaterial)
	}

	/// A capsule for the floating styles; for the notch, square top corners against the screen edge
	/// and rounded bottom ones.
	private var shape: some InsettableShape {
		PillShape(cornerRadius: metrics.cornerRadius, squareTopCorners: metrics.hugsTopEdge)
	}
}

/// The pill's outline: a rounded rectangle whose top corners can be squared off so the body appears
/// to hang from the screen's top edge rather than float below it.
private struct PillShape: InsettableShape {
	let cornerRadius: CGFloat
	let squareTopCorners: Bool
	var inset: CGFloat = 0

	func path(in rect: CGRect) -> Path {
		let rect = rect.insetBy(dx: inset, dy: inset)
		let radius = min(cornerRadius, rect.height / 2, rect.width / 2)
		guard squareTopCorners else {
			return Path(roundedRect: rect, cornerRadius: radius)
		}
		var path = Path()
		path.move(to: CGPoint(x: rect.minX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
		path.addQuadCurve(
			to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
			control: CGPoint(x: rect.maxX, y: rect.maxY))
		path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
		path.addQuadCurve(
			to: CGPoint(x: rect.minX, y: rect.maxY - radius),
			control: CGPoint(x: rect.minX, y: rect.maxY))
		path.closeSubpath()
		return path
	}

	/// Insets the outline so `strokeBorder` draws the 1 pt border inside the body rather than astride it.
	func inset(by amount: CGFloat) -> PillShape {
		var shape = self
		shape.inset += amount
		return shape
	}
}
