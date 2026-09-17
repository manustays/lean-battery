import Testing
@testable import SlimBatteryCore

@Suite struct PillStyleTests {
	@Test func defaultStyleKeepsTheShippedGeometry() {
		let metrics = PillMetrics(style: .medium)
		#expect(metrics.height == 46)
		#expect(metrics.minimumWidth == 240)
		#expect(metrics.maximumWidth == 400)
		#expect(metrics.iconWidth == 14)
		#expect(metrics.iconHeight == 28)
		#expect(metrics.titleFontSize == 13)
		#expect(metrics.detailFontSize == 11.5)
		#expect(metrics.horizontalPadding == 16)
		#expect(metrics.topGap == 8)
		#expect(!metrics.hugsTopEdge)
	}

	@Test func smallAndLargeScaleEveryDimension() {
		let small = PillMetrics(style: .small)
		let large = PillMetrics(style: .large)
		#expect(small.height == 46 * 0.85)
		#expect(small.titleFontSize == 13 * 0.85)
		#expect(small.iconHeight == 28 * 0.85)
		#expect(small.minimumWidth == 240 * 0.85)
		#expect(large.height == 46 * 1.2)
		#expect(large.titleFontSize == 13 * 1.2)
		#expect(large.iconHeight == 28 * 1.2)
		#expect(large.maximumWidth == 400 * 1.2)
	}

	@Test func iconKeepsItsOneToTwoAspectAtEverySize() {
		for style in PillStyle.allCases {
			let metrics = PillMetrics(style: style)
			#expect(metrics.iconHeight == metrics.iconWidth * 2)
		}
	}

	@Test func capsuleStylesStayCapsules() {
		for style in [PillStyle.small, .medium, .large] {
			let metrics = PillMetrics(style: style)
			#expect(metrics.cornerRadius == metrics.height / 2)
			#expect(!metrics.hugsTopEdge)
			#expect(metrics.topGap == 8)
		}
	}

	@Test func notchHugsTheTopEdgeWithItsOwnCorner() {
		let metrics = PillMetrics(style: .notch)
		#expect(metrics.hugsTopEdge)
		#expect(metrics.topGap == 0)
		// Not a capsule: the bottom corners are rounded, the top ones stay square against the screen edge.
		#expect(metrics.cornerRadius < metrics.height / 2)
	}

	@Test func everyStyleIsWideEnoughToBeReadable() {
		for style in PillStyle.allCases {
			let metrics = PillMetrics(style: style)
			#expect(metrics.minimumWidth >= 200)
			#expect(metrics.maximumWidth > metrics.minimumWidth)
			#expect(metrics.height > 0)
		}
	}

	@Test func rawValuesRoundTrip() {
		for style in PillStyle.allCases {
			#expect(PillStyle(rawValue: style.rawValue) == style)
		}
	}

	@Test func storedValueFallsBackToDefault() {
		#expect(PillStyle(stored: "large") == .large)
		#expect(PillStyle(stored: "notch") == .notch)
		#expect(PillStyle(stored: nil) == .medium)
		#expect(PillStyle(stored: "enormous") == .medium)
		#expect(PillStyle(stored: "") == .medium)
	}

	@Test func stylesAreOfferedSmallestFirstWithNotchLast() {
		#expect(PillStyle.allCases == [.small, .medium, .large, .notch])
		#expect(PillStyle.allCases.map(\.title) == ["Small", "Default", "Large", "Notch"])
	}
}
