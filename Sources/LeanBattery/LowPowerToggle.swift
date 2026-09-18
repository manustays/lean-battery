import Foundation
import LeanBatteryCore

/// Runs the Low Power Mode AppleScript through `osascript` without blocking the main thread.
enum LowPowerToggle {
	/// Asks for an admin password and sets Low Power Mode; resolves when `osascript` exits.
	static func set(_ enabled: Bool) async -> LowPowerCommand.Outcome {
		await Task.detached {
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
			process.arguments = ["-e", LowPowerCommand.appleScript(enable: enabled)]
			process.standardOutput = FileHandle.nullDevice
			let errorPipe = Pipe()
			process.standardError = errorPipe
			do {
				try process.run()
			} catch {
				return LowPowerCommand.Outcome.failed(error.localizedDescription)
			}
			// Drain stderr to EOF first so the child can never block on a full pipe; EOF means it exited.
			let message = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
			process.waitUntilExit()
			return LowPowerCommand.outcome(exitStatus: process.terminationStatus, standardError: message)
		}.value
	}
}
