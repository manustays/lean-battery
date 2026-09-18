import Testing
@testable import LeanBatteryCore

@Suite struct PillStyleTests {
	@Test func defaultStyleKeepsTheShippedGeometry() {
		let metrics = PillMetrics(style: .medium)
		#expect(metrics.height == 46)
		#expect(metrics.minimumWidth == 240)
		#expect(metrics.maximumWidth == 400)
		#expect(metrics.iconWidth == 11)
		#expect(metrics.iconHeight == 22)
		#expect(metrics.titleFontSize == 13)
		#expect(metrics.detailFontSize == 11.5)
		#expect(metrics.horizontalPadding == 22)
		#expect(metrics.topExtension == 0)
		#expect(metrics.totalHeight == metrics.height)
		#expect(metrics.topGap == 8)
		#expect(!metrics.hugsTopEdge)
	}

	@Test func smallAndLargeScaleEveryDimension() {
		let small = PillMetrics(style: .small)
		let large = PillMetrics(style: .large)
		#expect(small.height == 46 * 0.85)
		#expect(small.titleFontSize == 13 * 0.85)
		#expect(small.iconHeight == 22 * 0.85)
		#expect(small.minimumWidth == 240 * 0.85)
		#expect(large.height == 46 * 1.2)
		#expect(large.titleFontSize == 13 * 1.2)
		// Large grows the text and the box but not the glyph: 11 x 22 pt is as large as it renders crisply.
		#expect(large.iconHeight == 22)
		#expect(large.maximumWidth == 400 * 1.2)
	}

	@Test func iconIsNeverDrawnLargerThanTheGlyphIsRendered() {
		// IconRenderer draws 11 x 22 pt at 1x and 2x; anything wider is an upscale of that bitmap.
		for style in PillStyle.allCases {
			#expect(PillMetrics(style: style).iconWidth <= 11)
		}
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

	@Test func notchSizesItselfAgainstTheDisplaysOwnNotch() {
		let metrics = PillMetrics(style: .notch, notchWidth: 200, notchHeight: 32)
		// Only a little wider than the cutout, so it reads as the notch having grown.
		#expect(metrics.minimumWidth == 240)
		#expect(metrics.maximumWidth == 380)
		// The body is drawn up alongside the notch, and its content band sits below.
		#expect(metrics.topExtension == 32)
		#expect(metrics.totalHeight == metrics.height + 32)
	}

	@Test func aWiderNotchGivesAWiderBody() {
		let narrow = PillMetrics(style: .notch, notchWidth: 160, notchHeight: 32)
		let wide = PillMetrics(style: .notch, notchWidth: 220, notchHeight: 32)
		#expect(wide.minimumWidth - narrow.minimumWidth == 60)
	}

	@Test func aDisplayWithoutANotchDrawsNothingAboveTheContent() {
		// No cutout to fill beside, so the body is just the content band, flush to the top edge.
		let metrics = PillMetrics(style: .notch, notchWidth: PillMetrics.notchStubWidth, notchHeight: 0)
		#expect(metrics.topExtension == 0)
		#expect(metrics.totalHeight == metrics.height)
		#expect(metrics.hugsTopEdge)
	}

	@Test func onlyTheNotchStyleDrawsAboveItsContent() {
		for style in [PillStyle.small, .medium, .large] {
			#expect(PillMetrics(style: style, notchWidth: 200, notchHeight: 32).topExtension == 0)
		}
	}

	@Test func everyStyleIsWideEnoughToBeReadable() {
		for style in PillStyle.allCases {
			let metrics = PillMetrics(style: style, notchWidth: 200, notchHeight: 32)
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
