// Renders sample menubar icons to docs/assets/ using the app's own IconRenderer.
// ponytail: swiftc over the core sources, no extra target — run via scripts/sample-icons.sh.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Scale factor for the exported PNGs; the icon is vector, so this stays crisp.
let exportScale: CGFloat = 8

/// Sample states, one per documented battery stage.
let samples: [(name: String, state: BatteryState)] = [
	("discharging", BatteryState(percent: 78)),
	("charging", BatteryState(percent: 64, isCharging: true, isPluggedIn: true)),
	("low-battery", BatteryState(percent: 12)),
	("high-temperature", BatteryState(percent: 63, temperatureCelsius: 44, isHot: true)),
]

/// Writes `image` as a PNG at `url`, or exits with a message.
func writePNG(_ image: CGImage, to url: URL) {
	guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
		fatalError("cannot write \(url.path)")
	}
	CGImageDestinationAddImage(destination, image, nil)
	guard CGImageDestinationFinalize(destination) else { fatalError("cannot finalize \(url.path)") }
}

@main
struct SampleIcons {
	static func main() {
		let directory = URL(fileURLWithPath: "docs/assets")
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		for (name, state) in samples {
			for (suffix, isWhite) in [("", true), ("-light", false)] {
				guard let image = IconRenderer.render(IconSpec(state: state), foregroundIsWhite: isWhite, scale: exportScale) else {
					fatalError("render failed for \(name)")
				}
				let url = directory.appendingPathComponent("menubar-\(name)\(suffix).png")
				writePNG(image, to: url)
				print("wrote \(url.path) (\(image.width)×\(image.height))")
			}
		}
	}
}
