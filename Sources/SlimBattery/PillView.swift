import SwiftUI
import SlimBatteryCore

/// The floating capsule's contents (spec §6.3): battery icon, title, detail on a dark material capsule.
struct PillView: View {
	/// Capsule height; the panel is this plus two shadow insets.
	static let height: CGFloat = 46
	/// Narrowest the capsule is allowed to shrink to.
	static let minimumWidth: CGFloat = 240
	/// Widest the capsule is allowed to grow to before text truncates.
	static let maximumWidth: CGFloat = 400
	/// Transparent margin around the capsule so the drop shadow is not clipped by the window.
	static let shadowInset: CGFloat = 20

	let icon: NSImage
	let content: PillContent
	let onDismiss: () -> Void

	var body: some View {
		HStack(spacing: 10) {
			Image(nsImage: icon)
				.resizable()
				.frame(width: 14, height: 28)
			VStack(alignment: .leading, spacing: 1) {
				Text(content.title)
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(.white)
				Text(content.detail)
					.font(.system(size: 11.5))
					.foregroundStyle(.white.opacity(0.65))
			}
			.lineLimit(1)
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 16)
		// The clamp is the layout: short text grows to 240 pt, long text stops at 400 pt and truncates.
		.frame(minWidth: Self.minimumWidth, maxWidth: Self.maximumWidth, minHeight: Self.height, maxHeight: Self.height)
		.background(.ultraThinMaterial, in: Capsule())
		.overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
		.shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
		.environment(\.colorScheme, .dark)
		.contentShape(Capsule())
		.onTapGesture(perform: onDismiss)
		.padding(Self.shadowInset)
	}
}
