import Foundation
import IOKit
import IOKit.ps

/// Thin wrappers over IOKit power APIs. Not unit-tested; verified by running the app.
enum SystemPower {
	/// Description dictionary of the internal battery, or nil when the Mac has none.
	static func internalBatteryDescription() -> [String: Any]? {
		let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
		let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
		for source in sources {
			guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
			if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
				return description
			}
		}
		return nil
	}

	/// One property of the AppleSmartBattery registry entry (e.g. "Temperature"), or nil when missing.
	static func smartBatteryProperty(_ key: String) -> Any? {
		withSmartBattery { service in
			IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
		}
	}

	/// All AppleSmartBattery registry properties, or empty when unavailable. Heavier than a single-key read: popover use only.
	static func smartBatteryProperties() -> [String: Any] {
		withSmartBattery { service in
			var properties: Unmanaged<CFMutableDictionary>?
			guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
			return properties?.takeRetainedValue() as? [String: Any]
		} ?? [:]
	}

	/// Looks up the AppleSmartBattery service, runs `body`, and releases the service.
	private static func withSmartBattery<Result>(_ body: (io_service_t) -> Result?) -> Result? {
		let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
		guard service != IO_OBJECT_NULL else { return nil }
		defer { IOObjectRelease(service) }
		return body(service)
	}
}
