import Foundation

/// Label/value rows for the collapsible Battery Information section (spec §5.4).
public struct BatteryInfo: Equatable, Sendable {
	/// One row in the section.
	public struct Row: Equatable, Sendable, Identifiable {
		public var label: String
		public var value: String
		public var id: String { label }

		/// Creates a row.
		public init(label: String, value: String) {
			self.label = label
			self.value = value
		}
	}

	public var rows: [Row]

	/// Builds rows from the IOPS power source description and AppleSmartBattery properties; missing values show "—".
	public init(powerSource: [String: Any], registry: [String: Any]) {
		let maximum = registry["AppleRawMaxCapacity"] as? Int
		let design = registry["DesignCapacity"] as? Int
		var health: String?
		var capacity: String?
		if let maximum, let design, design > 0 {
			health = "\(Int((Double(maximum) * 100 / Double(design)).rounded()))%"
			capacity = "\(maximum) / \(design) mAh"
		}
		let condition = (powerSource["BatteryHealth"] as? String).flatMap { $0.isEmpty ? nil : $0 }
		let watts = ((registry["AdapterDetails"] as? [String: Any])?["Watts"] as? Int).flatMap { $0 > 0 ? $0 : nil }
		rows = [
			Row(label: "Health", value: health ?? "—"),
			Row(label: "Condition", value: condition ?? "—"),
			Row(label: "Cycle count", value: (registry["CycleCount"] as? Int).map(String.init) ?? "—"),
			Row(label: "Capacity", value: capacity ?? "—"),
			Row(label: "Voltage", value: (registry["Voltage"] as? Int).map { String(format: "%.2f V", Double($0) / 1000) } ?? "—"),
			Row(label: "Adapter", value: watts.map { "\($0) W" } ?? "—"),
		]
	}
}
