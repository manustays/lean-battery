import SwiftUI
import LeanBatteryCore

/// Compact popover (spec §5): header, Battery Information, footer; routes in place to settings or notifications.
struct PopoverView: View {
	@Bindable var model: PopoverModel

	var body: some View {
		VStack(spacing: 0) {
			if model.isShowingNotifications {
				NotificationsView(model: model, settings: model.notificationSettings)
			} else if model.isShowingSettings {
				SettingsView(model: model)
			} else {
				if let header = model.header {
					HeaderSection(header: header, model: model)
				} else {
					Text("Battery data unavailable")
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity)
						.padding(14)
				}
				Divider()
				EnergySection(model: model)
				Divider()
				BatteryInfoSection(model: model)
				Divider()
				SystemLinksSection()
				UpdateRowView(updates: model.updates)
				Divider()
				FooterSection(model: model)
			}
		}
		.font(.system(size: 12))
		.frame(width: 320)
	}
}

/// Percent, status line, source/draw/temp grid, charge bar, Low Power Mode row (spec §5.1).
private struct HeaderSection: View {
	let header: PowerHeader
	let model: PopoverModel

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .center) {
				VStack(alignment: .leading, spacing: 2) {
					Text(header.percentText)
						.font(.system(size: 30, weight: .bold))
						.monospacedDigit()
					Text(header.statusLine)
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
				}
				Spacer()
				Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
					GridRow {
						Text("Source").foregroundStyle(.secondary)
						Text(header.sourceText).lineLimit(1)
					}
					GridRow {
						Text("Draw").foregroundStyle(.secondary)
						Text(header.drawText).monospacedDigit()
					}
					GridRow {
						Text("Temp").foregroundStyle(.secondary)
						Text(header.temperatureText)
							.monospacedDigit()
							.foregroundStyle(header.isHot ? Color.red : Color.primary)
					}
				}
			}
			ChargeBar(fraction: header.fillFraction, color: fillColor)
			HStack(spacing: 6) {
				Text("Low Power Mode")
				Text(header.lowPowerModeText)
					.font(.system(size: 11))
					.foregroundStyle(.tertiary)
				Spacer()
				Toggle("Low Power Mode", isOn: Binding(get: { header.isLowPowerMode }, set: { model.setLowPowerMode($0) }))
					.toggleStyle(.switch)
					.controlSize(.mini)
					.labelsHidden()
					.disabled(model.isChangingLowPowerMode)
			}
			if let message = model.lowPowerModeMessage {
				Text(message)
					.font(.system(size: 11))
					.foregroundStyle(.red)
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
	}

	/// Bar color follows the icon's fill rule; the foreground role uses the primary label color.
	private var fillColor: Color {
		switch header.fill {
		case .foreground: .primary
		case .lowPower: .yellow
		case .charging: .green
		case .low: .red
		}
	}
}

/// 4 pt rounded charge bar.
private struct ChargeBar: View {
	let fraction: Double
	let color: Color

	var body: some View {
		GeometryReader { proxy in
			ZStack(alignment: .leading) {
				Capsule().fill(.quaternary)
				Capsule().fill(color).frame(width: proxy.size.width * fraction)
			}
		}
		.frame(height: 4)
	}
}

/// Collapsible Battery Information rows (spec §5.4).
private struct BatteryInfoSection: View {
	@Bindable var model: PopoverModel

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Button {
				model.isInfoExpanded.toggle()
			} label: {
				HStack {
					Text("BATTERY INFORMATION")
						.font(.system(size: 10, weight: .medium))
						.foregroundStyle(.secondary)
					Spacer()
					Image(systemName: model.isInfoExpanded ? "chevron.up" : "chevron.down")
						.font(.system(size: 10))
						.foregroundStyle(.secondary)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			if model.isInfoExpanded, let info = model.info {
				ForEach(info.rows) { row in
					HStack {
						Text(row.label).foregroundStyle(.secondary)
						Spacer()
						Text(row.value).monospacedDigit()
					}
				}
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 8)
	}
}

/// macOS's own battery screens, one click away.
private struct SystemLinksSection: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			SystemLinkRow(symbol: "bolt.fill", title: "Battery Settings", action: Self.openBatterySettings)
			SystemLinkRow(symbol: "chart.bar.fill", title: "Activity Monitor · Energy", action: Self.openActivityMonitorEnergy)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 8)
	}

	/// System Settings › Battery.
	private static func openBatterySettings() {
		guard let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") else { return }
		NSWorkspace.shared.open(url)
	}

	/// Activity Monitor on its Energy tab.
	private static func openActivityMonitorEnergy() {
		// ponytail: Activity Monitor takes no deep link — it reopens whichever tab it last showed. Setting that
		// preference (2 = Energy) lands on the right tab whenever it is not already running; if it is, it simply
		// comes forward on the tab the user left it on. Choosing the tab in a running app would need Accessibility.
		UserDefaults(suiteName: "com.apple.ActivityMonitor")?.set(2, forKey: "SelectedTab")
		let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
		NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
	}
}

/// One tappable row pointing at a macOS screen.
private struct SystemLinkRow: View {
	let symbol: String
	let title: String
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack(spacing: 6) {
				Image(systemName: symbol)
					.font(.system(size: 10))
					.foregroundStyle(.secondary)
					.frame(width: 14)
				Text(title)
				Spacer()
				Image(systemName: "arrow.up.forward")
					.font(.system(size: 9))
					.foregroundStyle(.tertiary)
			}
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
	}
}

/// App name and version on the left, Settings and Quit on the right (spec §5.5).
private struct FooterSection: View {
	let model: PopoverModel

	/// `CFBundleName`, so the footer never drifts from the bundle.
	private static let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "LeanBattery"
	private static let homepage = URL(string: "https://abhi.am/lean-battery")
	private static let releases = URL(string: UpdatePolicy.releasePrefix)

	var body: some View {
		HStack(spacing: 6) {
			Button(Self.appName) { Self.open(Self.homepage) }
				.help("Open the LeanBattery home page")
			Button("v\(model.updates.installedVersion)") { Self.open(Self.releases) }
				.monospacedDigit()
				.foregroundStyle(.tertiary)
				.help("Releases and changelog on GitHub")
			Spacer()
			Button { model.isShowingSettings = true } label: {
				Label("Settings", systemImage: "gearshape")
			}
			Button { NSApplication.shared.terminate(nil) } label: {
				Label("Quit", systemImage: "power")
			}
			.padding(.leading, 6)
		}
		.labelStyle(.titleAndIcon)
		.buttonStyle(.plain)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 14)
		.padding(.vertical, 8)
	}

	/// Opens a link, ignoring the impossible nil.
	private static func open(_ url: URL?) {
		guard let url else { return }
		NSWorkspace.shared.open(url)
	}
}

/// Apps using significant energy, with a range switch (spec §5.2).
private struct EnergySection: View {
	@Bindable var model: PopoverModel

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text("ENERGY")
					.font(.system(size: 10, weight: .medium))
					.foregroundStyle(.secondary)
				Spacer()
				Picker("Range", selection: $model.energyRange) {
					ForEach(EnergyRange.allCases) { range in
						Text(model.energyLabel(for: range)).tag(range)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.controlSize(.mini)
				.fixedSize()
			}
			content
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 8)
	}

	@ViewBuilder
	private var content: some View {
		switch model.energyState {
		case .loading:
			Text("Reading…")
				.foregroundStyle(.tertiary)
				.frame(maxWidth: .infinity, alignment: .leading)
		case .unavailable:
			Text("Energy data unavailable (macOS changed powerlog)")
				.font(.system(size: 11))
				.foregroundStyle(.secondary)
		case .empty(let message):
			Text(message)
				.font(.system(size: 11))
				.foregroundStyle(.secondary)
		case .rows(let rows):
			ForEach(rows) { row in
				EnergyRowView(row: row)
			}
		}
	}
}

/// One energy row: icon, name, bar, share.
private struct EnergyRowView: View {
	let row: EnergyRow

	var body: some View {
		HStack(spacing: 6) {
			icon
				.frame(width: 16, height: 16)
			Text(row.displayName)
				.lineLimit(1)
				.truncationMode(.tail)
			Spacer(minLength: 4)
			Capsule()
				.fill(.quaternary)
				.frame(width: 60, height: 4)
				.overlay(alignment: .leading) {
					Capsule()
						.fill(barColor)
						.frame(width: 60 * min(1, row.sharePercent / 100), height: 4)
				}
			Text("\(Int(row.sharePercent.rounded()))%")
				.monospacedDigit()
				.foregroundStyle(.secondary)
				.frame(width: 30, alignment: .trailing)
		}
	}

	/// The app's icon, or a neutral glyph for daemons and helpers that have none.
	@ViewBuilder
	private var icon: some View {
		if let image = AppCatalog.icon(for: row.id) {
			Image(nsImage: image).resizable()
		} else {
			Image(systemName: "gearshape")
				.foregroundStyle(.tertiary)
		}
	}

	/// Spec §5.2: ≥ 40 % orange, ≥ 15 % yellow, else secondary gray.
	private var barColor: Color {
		switch row.barLevel {
		case .high: Color(red: 255 / 255, green: 159 / 255, blue: 10 / 255)     // #FF9F0A
		case .medium: Color(red: 255 / 255, green: 214 / 255, blue: 10 / 255)   // #FFD60A
		case .low: Color.secondary
		}
	}
}
