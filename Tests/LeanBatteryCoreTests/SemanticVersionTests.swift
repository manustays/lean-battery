import Testing
@testable import LeanBatteryCore

@Suite struct SemanticVersionTests {
	@Test func parsesThreeComponentsWithAnOptionalLeadingV() {
		#expect(SemanticVersion("v1.2.3") == SemanticVersion("1.2.3"))
		#expect(SemanticVersion("0.1.0")?.minor == 1)
	}

	@Test func rejectsAnythingThatIsNotThreeStableComponents() {
		#expect(SemanticVersion("1.2") == nil)
		#expect(SemanticVersion("1.2.3.4") == nil)
		#expect(SemanticVersion("1.2.3-beta.1") == nil)
		#expect(SemanticVersion("1.2.x") == nil)
		#expect(SemanticVersion("") == nil)
		#expect(SemanticVersion("v") == nil)
		#expect(SemanticVersion("-1.0.0") == nil)
		#expect(SemanticVersion(" 1.0.0") == nil)
	}

	@Test func rejectsComponentsThatOverflow() {
		#expect(SemanticVersion("99999999999999999999.0.0") == nil)
	}

	@Test func ordersByMajorThenMinorThenPatch() {
		#expect(SemanticVersion("0.2.0")! > SemanticVersion("0.1.9")!)
		#expect(SemanticVersion("1.0.0")! > SemanticVersion("0.99.99")!)
		#expect(SemanticVersion("1.0.10")! > SemanticVersion("1.0.9")!)
		#expect(!(SemanticVersion("1.0.0")! > SemanticVersion("1.0.0")!))
	}
}
