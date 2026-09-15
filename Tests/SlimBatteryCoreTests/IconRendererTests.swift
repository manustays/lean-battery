import CoreGraphics
import Testing
@testable import SlimBatteryCore

/// RGBA reader for rendered icons, addressed in icon points (top-left origin).
private struct Pixels {
	let scale: Double
	let width: Int
	private let bytes: [UInt8]

	init(_ image: CGImage, scale: Double) {
		self.scale = scale
		width = image.width
		var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
		buffer.withUnsafeMutableBytes { raw in
			let context = CGContext(
				data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
				bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			)!
			context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
		}
		bytes = buffer
	}

	/// Pixel covering the point (x, y).
	func at(_ x: Double, _ y: Double) -> [UInt8] {
		let index = (Int(y * scale) * width + Int(x * scale)) * 4
		return Array(bytes[index..<index + 4])
	}

	/// Pixels in a point-space rectangle.
	func region(x: ClosedRange<Double>, y: ClosedRange<Double>) -> [[UInt8]] {
		stride(from: y.lowerBound, through: y.upperBound, by: 1 / scale).flatMap { row in
			stride(from: x.lowerBound, through: x.upperBound, by: 1 / scale).map { at($0, row) }
		}
	}
}

/// Renders a state at 4× for pixel sampling.
private func render(_ state: BatteryState) throws -> Pixels {
	let image = try #require(IconRenderer.render(IconSpec(state: state), foregroundIsWhite: true, scale: 4))
	return Pixels(image, scale: 4)
}

@Suite struct IconRendererTests {
	@Test func rendersAtRequestedScale() throws {
		let image = try #require(IconRenderer.render(IconSpec(state: BatteryState(percent: 57)), foregroundIsWhite: true, scale: 2))
		#expect(image.width == 22)
		#expect(image.height == 44)
	}

	@Test func bodyStrokeIsForeground() throws {
		#expect(try render(BatteryState(percent: 57)).at(0.6, 12) == [255, 255, 255, 255])
	}

	@Test func emptyPartOfBodyIsTransparent() throws {
		#expect(try render(BatteryState(percent: 50)).at(3, 5)[3] == 0)
	}

	@Test func chargingFillIsGreen() throws {
		let pixel = try render(BatteryState(percent: 50, isCharging: true, isPluggedIn: true)).at(3, 19)
		#expect(pixel[3] == 255)
		#expect(pixel[1] > 180 && pixel[0] < 80 && pixel[2] < 120)
	}

	@Test func foregroundFillKnocksNumberOutToTransparent() throws {
		let glyphArea = try render(BatteryState(percent: 88)).region(x: 2...9, y: 9...15)
		#expect(glyphArea.contains { $0[3] == 0 })
	}

	@Test func coloredFillDrawsNumberInBlack() throws {
		let glyphArea = try render(BatteryState(percent: 88, isLowPowerMode: true)).region(x: 2...9, y: 9...15)
		#expect(!glyphArea.contains { $0[3] == 0 })
		#expect(glyphArea.contains { $0[0] < 40 && $0[1] < 40 && $0[2] < 40 && $0[3] == 255 })
	}

	@Test func plugReplacesNumberInsideFill() throws {
		let glyphArea = try render(BatteryState(percent: 100, isPluggedIn: true)).region(x: 3...8, y: 9...15)
		#expect(glyphArea.contains { $0[3] == 0 })
	}

	@Test func hotBadgeIsRedWithTransparentRing() throws {
		let hot = try render(BatteryState(percent: 57, isHot: true))
		let badge = hot.at(8.9, 2.3)
		#expect(badge[0] > 220 && badge[1] < 100 && badge[3] == 255)
		// (10.3, 4.3) is on the body's rounded corner stroke, 2.4–2.7pt from the badge center: inside the cleared ring.
		#expect(hot.at(10.3, 4.3)[3] == 0)
		#expect(try render(BatteryState(percent: 57)).at(10.3, 4.3)[3] == 255)
	}
}
