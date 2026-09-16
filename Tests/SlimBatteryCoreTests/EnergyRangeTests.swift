import Testing
@testable import SlimBatteryCore

@Suite struct EnergyRangeTests {
	@Test func rangeSeconds() {
		#expect(EnergyRange.now.seconds == 300)
		#expect(EnergyRange.eightHours.seconds == 28_800)
		#expect(EnergyRange.day.seconds == 86_400)
		#expect(EnergyRange.week.seconds == 604_800)
	}

	@Test func fullLabels() {
		#expect(EnergyRange.allCases.map(\.label) == ["Now", "8h", "24h", "7d"])
	}

	@Test func labelShowsFullRangeWhenHistoryIsLongEnough() {
		#expect(EnergyRange.week.label(covering: 604_800) == "7d")
		#expect(EnergyRange.week.label(covering: 900_000) == "7d")
	}

	@Test func labelShowsRealSpanWhenHistoryIsShort() {
		// 6.2 days of history under a 7d selection → "6d" (spec §5.2).
		#expect(EnergyRange.week.label(covering: 6.2 * 86_400) == "6d")
		#expect(EnergyRange.day.label(covering: 5 * 3_600) == "5h")
		#expect(EnergyRange.eightHours.label(covering: 90 * 60) == "1h")
		#expect(EnergyRange.now.label(covering: 120) == "2m")
	}

	@Test func shortSpanNeverShowsZero() {
		#expect(EnergyRange.now.label(covering: 10) == "1m")
	}

	@Test func emptyTextDependsOnRange() {
		#expect(EnergyRange.now.emptyText == "No activity in the last 5 min")
		#expect(EnergyRange.day.emptyText == "No data for this range")
	}

	@Test(arguments: [(5.0, EnergyRow.BarLevel.low), (15.0, .medium), (39.9, .medium), (40.0, .high)])
	func barLevelThresholds(share: Double, expected: EnergyRow.BarLevel) {
		let row = EnergyRow(id: "com.a", displayName: "A", sharePercent: share, isApplication: true)
		#expect(row.barLevel == expected)
	}
}
