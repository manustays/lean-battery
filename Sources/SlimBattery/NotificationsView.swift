import SwiftUI
import SlimBatteryCore

/// Notification preferences (spec §6.1): up to five battery rules, power-change alerts, duration, and a preview.
struct NotificationsView: View {
	/// The popover's shared model; only `previewNotification()` is used here.
	@Bindable var model: PopoverModel
	/// Bound separately from `model` so the rule rows get direct bindings into the store.
	@Bindable var settings: NotificationSettings

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			header
			Divider()
			rules
			Divider()
			powerChanges
			Divider()
			duration
			style
			Button("Preview notification") { model.previewNotification() }
				.frame(maxWidth: .infinity)
		}
		.padding(14)
	}

	/// Back to the main settings page.
	private var header: some View {
		HStack {
			Button("‹ Settings") { model.isShowingNotifications = false }
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)
			Spacer()
			Text("Notifications").font(.system(size: 13, weight: .semibold))
			Spacer()
			Color.clear.frame(width: 60, height: 1)
		}
	}

	/// Rule list with the `n / 5` counter and the add button.
	private var rules: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text("BATTERY RULES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
				Spacer()
				Text("\(settings.rules.count) / \(NotificationRule.maximumCount)")
					.font(.system(size: 10))
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
			ForEach($settings.rules) { $rule in
				RuleRow(rule: $rule) { settings.removeRule(id: rule.id) }
			}
			Button("＋ Add rule") { settings.addRule() }
				.buttonStyle(.plain)
				.foregroundStyle(settings.canAddRule ? Color.accentColor : Color.secondary)
				.disabled(!settings.canAddRule)
		}
	}

	/// Connected / disconnected alerts and their sound chip.
	private var powerChanges: some View {
		HStack {
			Toggle("", isOn: $settings.powerChangeAlerts)
				.toggleStyle(.switch)
				.controlSize(.mini)
				.labelsHidden()
			Text("Connected / disconnected")
			Spacer()
			ChipToggle(title: "Sound", isOn: $settings.powerChangeSound)
				.disabled(!settings.powerChangeAlerts)
		}
	}

	/// Duration slider, 2–10 s in whole seconds.
	private var duration: some View {
		HStack {
			Text("Duration")
			Slider(
				value: Binding(
					get: { Double(settings.duration) },
					set: { settings.duration = Int($0.rounded()) }),
				in: Double(NotificationSettings.durationRange.lowerBound)...Double(NotificationSettings.durationRange.upperBound),
				step: 1)
			Text("\(settings.duration)s").monospacedDigit().frame(width: 26, alignment: .trailing)
		}
	}

	/// Pill size, plus the notch style that hugs the screen's top edge.
	private var style: some View {
		HStack {
			Text("Style")
			Spacer()
			Picker("", selection: $settings.pillStyle) {
				ForEach(PillStyle.allCases, id: \.self) { style in
					Text(style.title).tag(style)
				}
			}
			.labelsHidden()
			.pickerStyle(.segmented)
			.controlSize(.small)
			.frame(width: 232)
		}
	}
}

/// One rule row: enable switch, direction, threshold stepper, glow and sound chips, delete (spec §6.1).
private struct RuleRow: View {
	/// The rule this row edits.
	@Binding var rule: NotificationRule
	/// Called when the user taps the trash button.
	let onDelete: () -> Void

	var body: some View {
		// The row has 292 pt to spend (320 pt popover less 14 pt padding a side) and a below-direction
		// row is the widest, since it alone adds the Glow chip. `.fixedSize()` is no help on the
		// Picker: an NSPopUpButton's intrinsic width fits its *longest* menu item, so it claimed
		// ~133 pt whichever direction was selected and squeezed the chips until their labels wrapped
		// one letter per line. The Picker now takes a fixed share and everything else is incompressible.
		HStack(spacing: 3) {
			Toggle("", isOn: $rule.isEnabled)
				.toggleStyle(.switch)
				.controlSize(.mini)
				.labelsHidden()
			Picker("", selection: $rule.direction) {
				Text("Below").tag(NotificationRule.Direction.below)
				Text("Above (charging)").tag(NotificationRule.Direction.above)
			}
			.labelsHidden()
			.pickerStyle(.menu)
			.controlSize(.small)
			.frame(width: 108)
			Text("\(rule.threshold)%").monospacedDigit().frame(width: 28, alignment: .trailing)
			Stepper("", value: $rule.threshold, in: NotificationRule.thresholdRange)
				.labelsHidden()
				.controlSize(.small)
			if rule.direction == .below {
				ChipToggle(title: "Glow", isOn: $rule.glow)
			}
			ChipToggle(title: "Sound", isOn: $rule.sound)
			Button {
				onDelete()
			} label: {
				Image(systemName: "trash").foregroundStyle(.secondary)
			}
			.buttonStyle(.plain)
		}
		.opacity(rule.isEnabled ? 1 : 0.5)
	}
}

/// Small on/off chip used for the Glow and Sound options.
private struct ChipToggle: View {
	/// The chip's label, e.g. "Glow" or "Sound".
	let title: String
	/// Whether the chip is currently on.
	@Binding var isOn: Bool

	var body: some View {
		Button {
			isOn.toggle()
		} label: {
			Text(title)
				.font(.system(size: 10, weight: .medium))
				// Without this the chip is the row's only compressible view, so any overflow
				// elsewhere wraps the label to one letter per line instead of showing up as a clip.
				.lineLimit(1)
				.fixedSize()
				.padding(.horizontal, 6)
				.padding(.vertical, 2)
				.background(isOn ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12), in: Capsule())
				.foregroundStyle(isOn ? Color.accentColor : Color.secondary)
		}
		.buttonStyle(.plain)
	}
}
