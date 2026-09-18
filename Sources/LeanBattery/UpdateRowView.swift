import SwiftUI
import LeanBatteryCore

/// The popover's update row (spec §13.3). Renders nothing unless an update is actually on offer.
struct UpdateRowView: View {
	let updates: UpdateService

	var body: some View {
		if case .available(let version, _) = updates.status {
			VStack(spacing: 0) {
				Divider()
				HStack(spacing: 8) {
					Text("Update available: v\(version)")
						.lineLimit(1)
					Spacer(minLength: 4)
					Button("Download") { updates.openDownloadPage() }
					Button("Homebrew") { updates.copyBrewCommand() }
						.help("Copies “\(UpdateService.brewCommand)”. The tap follows a release within about a day.")
					Button {
						updates.dismissCurrentOffer()
					} label: {
						Image(systemName: "xmark")
							.font(.system(size: 9, weight: .semibold))
					}
					.help("Hide this version")
				}
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)
				.padding(.horizontal, 14)
				.padding(.vertical, 6)
			}
		}
	}
}

/// The settings block: the opt-out switch, the status line, and a manual check.
struct UpdateSettingsBlock: View {
	@Bindable var model: PopoverModel

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack {
				Text("Check for updates")
				Spacer()
				Button("Check now") { model.updates.check(manual: true) }
					.buttonStyle(.plain)
					.foregroundStyle(model.updates.isEnabled ? Color.accentColor : Color.secondary)
					.disabled(!model.updates.isEnabled)
				Toggle("Check for updates", isOn: Binding(
					get: { model.updates.isEnabled },
					set: { model.updates.isEnabled = $0 }))
					.toggleStyle(.switch)
					.controlSize(.mini)
					.labelsHidden()
			}
			Text(statusText)
				.font(.system(size: 11))
				.foregroundStyle(.secondary)
		}
	}

	/// Spec §13.3's status strings, one per state.
	private var statusText: String {
		switch model.updates.status {
		case .disabled: "Version \(model.updates.installedVersion)"
		case .idle: "Checks once a day when you open this popover."
		case .checking: "Checking…"
		case .current(let version): "Up to date (v\(version))"
		case .available(let version, _): "Version \(version) is available."
		case .noReleases: "No releases yet"
		case .failed(let reason): "Couldn't check — \(reason)"
		}
	}
}
