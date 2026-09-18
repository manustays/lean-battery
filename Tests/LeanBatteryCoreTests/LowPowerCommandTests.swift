import Testing
@testable import LeanBatteryCore

@Suite struct LowPowerCommandTests {
	@Test(arguments: [(true, "lowpowermode 1"), (false, "lowpowermode 0")])
	func scriptRunsPmsetWithAdminPrivileges(enable: Bool, fragment: String) {
		let script = LowPowerCommand.appleScript(enable: enable)
		#expect(script.contains("/usr/bin/pmset -a \(fragment)"))
		#expect(script.hasSuffix("with administrator privileges"))
	}

	@Test func successIsChanged() {
		#expect(LowPowerCommand.outcome(exitStatus: 0, standardError: "") == .changed)
	}

	@Test func userCancelIsCancelled() {
		#expect(LowPowerCommand.outcome(exitStatus: 1, standardError: "0:180: execution error: User canceled. (-128)\n") == .cancelled)
	}

	@Test func otherErrorsCarryTrimmedMessage() {
		#expect(LowPowerCommand.outcome(exitStatus: 1, standardError: "  0:10: execution error: pmset failed (1)\n") == .failed("0:10: execution error: pmset failed (1)"))
	}
}
