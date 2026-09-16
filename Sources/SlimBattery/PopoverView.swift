import SwiftUI
import SlimBatteryCore

/// Compact popover (spec §5): header, Battery Information, footer; swaps to settings in place.
struct PopoverView: View {
	@Bindable var model: PopoverModel

	var body: some View {
		VStack(spacing: 0) {
			if model.isShowingSettings {
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

/// Settings and Quit (spec §5.5).
private struct FooterSection: View {
	let model: PopoverModel

	var body: some View {
		HStack {
			Button("Settings") { model.isShowingSettings = true }
			Spacer()
			Button("Quit") { NSApplication.shared.terminate(nil) }
		}
		.buttonStyle(.plain)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 14)
		.padding(.vertical, 8)
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
		case .high: Color(red: 1.0, green: 0.62, blue: 0.04)
		case .medium: Color(red: 1.0, green: 0.84, blue: 0.04)
		case .low: Color.secondary
		}
	}
}
