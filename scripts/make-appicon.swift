#!/usr/bin/env swift
// Draws Resources/AppIcon.png (1024×1024) — the menubar battery mark on a charcoal squircle.
// Run: swift scripts/make-appicon.swift
// ponytail: CoreGraphics + ImageIO are in the SDK; no asset catalog, no design tool, no dependency.
// The proportions mirror Sources/LeanBatteryCore/IconRenderer.swift (an 11×22 upright battery),
// so the app icon and the menubar icon read as the same object.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas = 1024.0
/// macOS app icons leave a margin: the rounded square covers ~80% of the canvas.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let plateRadius = 185.0

/// The menubar mark is 11×22 pt; these are its parts expressed in that coordinate space.
let markSize = CGSize(width: 11, height: 22)
let cap = CGRect(x: 3.5, y: 0.4, width: 4.0, height: 1.6)
let body = CGRect(x: 0.45, y: 2.2, width: 10.1, height: 19.4)
let inner = CGRect(x: 1.35, y: 3.1, width: 8.3, height: 17.6)
let bodyStrokeWidth = 0.9
/// How much of the inner area the charge fill covers.
let fillFraction = 0.7

guard
	let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
	let context = CGContext(
		data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
		space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
	FileHandle.standardError.write(Data("could not create the bitmap context\n".utf8))
	exit(1)
}

context.setShouldAntialias(true)
context.interpolationQuality = .high

// Charcoal plate with a soft top-to-bottom lift, so the square does not read as flat black.
let plateePath = CGPath(roundedRect: plate, cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil)
context.saveGState()
context.addPath(plateePath)
context.clip()
let top = CGColor(colorSpace: colorSpace, components: [0.208, 0.220, 0.239, 1.0])!
let bottom = CGColor(colorSpace: colorSpace, components: [0.106, 0.114, 0.129, 1.0])!
if let gradient = CGGradient(colorsSpace: colorSpace, colors: [top, bottom] as CFArray, locations: [0, 1]) {
	context.drawLinearGradient(
		gradient,
		start: CGPoint(x: plate.midX, y: plate.maxY),
		end: CGPoint(x: plate.midX, y: plate.minY),
		options: [])
}
context.restoreGState()

// Place the mark centred on the plate, at 62% of its height.
let markHeight = plate.height * 0.62
let scale = markHeight / markSize.height
let markWidth = markSize.width * scale
let originX = plate.midX - markWidth / 2
let originY = plate.midY - markHeight / 2

/// Maps a rect from the 11×22 mark space (origin top-left, as IconRenderer measures it) into the canvas.
func placed(_ rect: CGRect) -> CGRect {
	CGRect(
		x: originX + rect.minX * scale,
		y: originY + (markSize.height - rect.maxY) * scale,
		width: rect.width * scale,
		height: rect.height * scale)
}

let white = CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1])!
/// System green, the charging/healthy fill.
let green = CGColor(colorSpace: colorSpace, components: [0.188, 0.820, 0.345, 1.0])!

// Cap.
let capRect = placed(cap)
context.setFillColor(white)
context.addPath(CGPath(
	roundedRect: capRect,
	cornerWidth: capRect.height * 0.35, cornerHeight: capRect.height * 0.35, transform: nil))
context.fillPath()

// Charge fill, growing from the bottom of the inner area.
let innerRect = placed(inner)
let fillHeight = innerRect.height * fillFraction
let fillRect = CGRect(x: innerRect.minX, y: innerRect.minY, width: innerRect.width, height: fillHeight)
let fillRadius = innerRect.width * 0.18
context.setFillColor(green)
context.addPath(CGPath(roundedRect: fillRect, cornerWidth: fillRadius, cornerHeight: fillRadius, transform: nil))
context.fillPath()

// Body outline, drawn last so it sits over the fill's edge.
let bodyRect = placed(body)
let stroke = bodyStrokeWidth * scale
let bodyRadius = bodyRect.width * 0.22
context.setStrokeColor(white)
context.setLineWidth(stroke)
context.addPath(CGPath(
	roundedRect: bodyRect.insetBy(dx: stroke / 2, dy: stroke / 2),
	cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil))
context.strokePath()

guard let image = context.makeImage() else {
	FileHandle.standardError.write(Data("could not render the image\n".utf8))
	exit(1)
}

let output = URL(fileURLWithPath: "Resources/AppIcon.png")
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
	FileHandle.standardError.write(Data("could not open \(output.path) for writing\n".utf8))
	exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
	FileHandle.standardError.write(Data("could not write \(output.path)\n".utf8))
	exit(1)
}
print("wrote \(output.path) (\(Int(canvas))×\(Int(canvas)))")
