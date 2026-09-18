import Testing
@testable import LeanBatteryCore

@Suite struct EnergyNameTests {
	@Test func junkIsRejected() {
		// The only malformed value on a real Mac — it reached rank 5 in a Now window.
		#expect(EnergyName.isJunk("$(PRODUCT_BUNDLE_IDENTIFIER)"))
		#expect(EnergyName.isJunk(""))
	}

	@Test func realIdentifiersAreNotJunk() {
		#expect(!EnergyName.isJunk("com.apple.WindowServer"))
		#expect(!EnergyName.isJunk("sh.brew.sketchybar"))
	}

	@Test func trailingUUIDIsStripped() {
		#expect(EnergyName.canonical("com.apple.Safari.WebApp.9CC63388-ACFD-4F04-AC6A-759B3B85839B") == "com.apple.Safari.WebApp")
		#expect(EnergyName.canonical("com.apple.loginwindow.E6BA5579-AEEC-419C-9713-E9EA58006AB8") == "com.apple.loginwindow")
		#expect(EnergyName.canonical("com.apple.neagent.878568F8-CCE5-4157-8315-22F20DC8FB0A") == "com.apple.neagent")
	}

	@Test func nonUUIDSuffixesAreKept() {
		#expect(EnergyName.canonical("com.apple.XProtect.agent.scan") == "com.apple.XProtect.agent.scan")
		#expect(EnergyName.canonical("com.stablyai.orca.ShipIt") == "com.stablyai.orca.ShipIt")
	}

	@Test func appleNamesDropTheApplePrefix() {
		#expect(EnergyName.fallbackDisplayName(for: "com.apple.WindowServer") == "WindowServer")
		#expect(EnergyName.fallbackDisplayName(for: "com.apple.audio.coreaudiod") == "audio.coreaudiod")
		#expect(EnergyName.fallbackDisplayName(for: "com.apple.XProtect.agent.scan") == "XProtect.agent.scan")
	}

	@Test func otherNamesUseTheLastComponent() {
		// The top consumer on a real Mac (40.93 % over 24 h) resolves to no app.
		#expect(EnergyName.fallbackDisplayName(for: "sh.brew.sketchybar") == "sketchybar")
		#expect(EnergyName.fallbackDisplayName(for: "com.stablyai.orca") == "orca")
	}

	@Test func namesWithoutDotsSurviveIntact() {
		#expect(EnergyName.fallbackDisplayName(for: "kernel_task") == "kernel_task")
	}
}
