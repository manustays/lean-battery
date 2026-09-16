import Foundation
import SlimBatteryCore

/// Runs the Low Power Mode AppleScript through `osascript` without blocking the main thread.
enum LowPowerToggle {
	/// Asks for an admin password and sets Low Power Mode; resolves when `osascript` exits.
	static func set(_ enabled: Bool) async -> LowPowerCommand.Outcome {
		await withCheckedContinuation { continuation in
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
			process.arguments = ["-e", LowPowerCommand.appleScript(enable: enabled)]
			process.standardOutput = FileHandle.nullDevice
			let errorPipe = Pipe()
			process.standardError = errorPipe
			process.terminationHandler = { finished in
				let message = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
				continuation.resume(returning: LowPowerCommand.outcome(exitStatus: finished.terminationStatus, standardError: message))
			}
			do {
				try process.run()
			} catch {
				continuation.resume(returning: .failed(error.localizedDescription))
			}
		}
	}
}
