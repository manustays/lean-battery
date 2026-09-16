import Foundation

/// Builds the admin AppleScript that runs `pmset` and interprets `osascript`'s result (spec §8.5).
public enum LowPowerCommand {
	/// Result of one toggle attempt.
	public enum Outcome: Equatable, Sendable {
		case changed
		case cancelled
		case failed(String)
	}

	/// AppleScript that sets Low Power Mode for all power sources, prompting for an admin password.
	public static func appleScript(enable: Bool) -> String {
		"do shell script \"/usr/bin/pmset -a lowpowermode \(enable ? 1 : 0)\" with prompt \"SlimBattery wants to change Low Power Mode.\" with administrator privileges"
	}

	/// Maps `osascript`'s exit status and stderr to an outcome; AppleScript error -128 means the user cancelled.
	public static func outcome(exitStatus: Int32, standardError: String) -> Outcome {
		if exitStatus == 0 { return .changed }
		if standardError.contains("(-128)") { return .cancelled }
		return .failed(standardError.trimmingCharacters(in: .whitespacesAndNewlines))
	}
}
