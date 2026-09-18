import Testing
@testable import LeanBatteryCore

/// Treats anything starting with "app." as an installed application.
private func isApp(_ id: String) -> Bool { id.hasPrefix("app.") }
private func name(_ id: String) -> String { EnergyName.fallbackDisplayName(for: id) }

@Suite struct EnergyAggregatorTests {
	@Test func sharesAreComputedOverEveryRow() {
		let rows = EnergyAggregator.rows(
			sums: ["app.a": 60, "app.b": 40],
			displayName: name, isApplication: isApp)
		#expect(rows.map(\.id) == ["app.a", "app.b"])
		#expect(abs(rows[0].sharePercent - 60) < 0.001)
		#expect(abs(rows[1].sharePercent - 40) < 0.001)
	}

	@Test func junkNeverAppears() {
		// $(PRODUCT_BUNDLE_IDENTIFIER) reached rank 5 in a real Now window.
		let rows = EnergyAggregator.rows(
			sums: ["app.a": 50, "$(PRODUCT_BUNDLE_IDENTIFIER)": 50],
			displayName: name, isApplication: isApp)
		#expect(rows.map(\.id) == ["app.a"])
		// Its energy is excluded from the total too, so the survivor is 100 %.
		#expect(abs(rows[0].sharePercent - 100) < 0.001)
	}

	@Test func idsMergeAfterUUIDStripping() {
		let rows = EnergyAggregator.rows(
			sums: [
				"com.apple.Safari.WebApp.9CC63388-ACFD-4F04-AC6A-759B3B85839B": 30,
				"com.apple.Safari.WebApp.11111111-2222-3333-4444-555555555555": 70,
			],
			displayName: name, isApplication: { _ in false })
		#expect(rows.count == 1)
		#expect(rows[0].id == "com.apple.Safari.WebApp")
		#expect(abs(rows[0].sharePercent - 100) < 0.001)
	}

	@Test func applicationsAreAlwaysEligible() {
		// app.small ranks 7th but is an app, so it survives; sys.* rows below the top 5 do not.
		let sums: [String: Double] = [
			"sys.1": 300, "sys.2": 250, "sys.3": 200, "sys.4": 150, "sys.5": 100,
			"sys.6": 50, "app.small": 40,
		]
		let rows = EnergyAggregator.rows(sums: sums, displayName: name, isApplication: isApp, limit: 6)
		#expect(rows.contains { $0.id == "app.small" })
		#expect(!rows.contains { $0.id == "sys.6" })
	}

	@Test func nonAppsRankingInTheTopFiveAreKept() {
		// sketchybar is the real top consumer (40.93 % over 24 h) and resolves to no app.
		let rows = EnergyAggregator.rows(
			sums: ["sh.brew.sketchybar": 90, "app.a": 10],
			displayName: name, isApplication: isApp)
		#expect(rows.first?.id == "sh.brew.sketchybar")
		#expect(rows.first?.displayName == "sketchybar")
		#expect(rows.first?.isApplication == false)
	}

	@Test func rowsUnderOnePercentAreDropped() {
		let rows = EnergyAggregator.rows(
			sums: ["app.a": 995, "app.b": 5],
			displayName: name, isApplication: isApp)
		#expect(rows.map(\.id) == ["app.a"])
	}

	@Test func atMostFiveRows() {
		let sums = Dictionary(uniqueKeysWithValues: (1...9).map { ("app.\($0)", Double(100 - $0)) })
		#expect(EnergyAggregator.rows(sums: sums, displayName: name, isApplication: isApp).count == 5)
	}

	@Test func emptyInputProducesNoRows() {
		#expect(EnergyAggregator.rows(sums: [:], displayName: name, isApplication: isApp).isEmpty)
	}

	@Test func zeroTotalProducesNoRowsRatherThanDividingByZero() {
		#expect(EnergyAggregator.rows(sums: ["app.a": 0], displayName: name, isApplication: isApp).isEmpty)
	}

	@Test func isApplicationStopsOnceTheLimitIsReached() {
		// Three high-value apps satisfy limit: 3 on their own; 50 low-value, non-top-5,
		// non-app rows follow. isApplication must never be probed for any of those 50 —
		// that unbounded fan-out is the main-thread freeze this test guards against.
		final class Counter { var calls = 0 }
		let counter = Counter()
		var sums: [String: Double] = [:]
		for i in 1...3 { sums["app.\(i)"] = 100 - Double(i) }
		for i in 1...50 { sums["sys.\(i)"] = 0.01 }
		let rows = EnergyAggregator.rows(
			sums: sums,
			displayName: name,
			isApplication: { id in
				counter.calls += 1
				return id.hasPrefix("app.")
			},
			limit: 3)
		#expect(rows.map(\.id) == ["app.1", "app.2", "app.3"])
		#expect(counter.calls == 3)
	}

	@Test func displayNameComesFromTheResolver() {
		let rows = EnergyAggregator.rows(
			sums: ["app.orca": 100],
			displayName: { _ in "Orca" }, isApplication: isApp)
		#expect(rows[0].displayName == "Orca")
		#expect(rows[0].isApplication)
	}
}
