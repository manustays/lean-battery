import SwiftUI

/// Inline settings (spec §5.5): hot threshold, launch at login, and the `Notifications ›` row.
struct SettingsView: View {
	@Bindable var model: PopoverModel

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				Button("‹ Back") { model.isShowingSettings = false }
					.buttonStyle(.plain)
					.foregroundStyle(.secondary)
				Spacer()
				Text("Settings").font(.system(size: 13, weight: .semibold))
				Spacer()
				Color.clear.frame(width: 40, height: 1)
			}
			Divider()
			HStack {
				Text("High temp alert at")
				Spacer()
				Text("\(Int(model.hotThresholdCelsius)) °C").monospacedDigit()
				Stepper("High temp alert at", value: $model.hotThresholdCelsius, in: 30...60, step: 1)
					.labelsHidden()
			}
			VStack(alignment: .leading, spacing: 2) {
				HStack {
					Text("Launch at login")
					Spacer()
					Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
						.toggleStyle(.switch)
						.controlSize(.mini)
						.labelsHidden()
				}
				if let message = model.launchAtLoginMessage {
					Text(message)
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
				}
			}
			Divider()
			Button {
				model.isShowingNotifications = true
			} label: {
				HStack {
					Text("Notifications")
					Spacer()
					Text("›").foregroundStyle(.secondary)
				}
				.contentShape(.rect)
			}
			.buttonStyle(.plain)
		}
		.padding(14)
	}
}
