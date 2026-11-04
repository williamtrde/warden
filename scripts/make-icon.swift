#!/usr/bin/env swift
// Draws the app icon at every required size. Usage: swift scripts/make-icon.swift <appiconset folder>
import AppKit

func shieldPath(in rect: CGRect) -> NSBezierPath {
    let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
    let path = NSBezierPath()
    path.move(to: CGPoint(x: x + w / 2, y: y + h))
    path.curve(to: CGPoint(x: x + w, y: y + h * 0.84),
               controlPoint1: CGPoint(x: x + w * 0.66, y: y + h * 0.93), controlPoint2: CGPoint(x: x + w * 0.84, y: y + h * 0.86))
    path.curve(to: CGPoint(x: x + w / 2, y: y),
               controlPoint1: CGPoint(x: x + w * 1.02, y: y + h * 0.42), controlPoint2: CGPoint(x: x + w * 0.80, y: y + h * 0.14))
    path.curve(to: CGPoint(x: x, y: y + h * 0.84),
               controlPoint1: CGPoint(x: x + w * 0.20, y: y + h * 0.14), controlPoint2: CGPoint(x: x - w * 0.02, y: y + h * 0.42))
    path.curve(to: CGPoint(x: x + w / 2, y: y + h),
               controlPoint1: CGPoint(x: x + w * 0.16, y: y + h * 0.86), controlPoint2: CGPoint(x: x + w * 0.34, y: y + h * 0.93))
    path.close()
    return path
}

func render(size: Int) -> Data {
    let scale = CGFloat(size) / 1024
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(colors: [
        NSColor(red: 0.07, green: 0.11, blue: 0.20, alpha: 1),
        NSColor(red: 0.05, green: 0.27, blue: 0.33, alpha: 1)
    ])!.draw(in: squircle, angle: -70)

    let shieldRect = CGRect(x: 277, y: 220, width: 470, height: 590)
    NSGradient(colors: [
        NSColor(red: 0.20, green: 0.90, blue: 0.62, alpha: 1),
        NSColor(red: 0.08, green: 0.66, blue: 0.56, alpha: 1)
    ])!.draw(in: shieldPath(in: shieldRect), angle: -90)

    let check = NSBezierPath()
    check.move(to: CGPoint(x: 395, y: 520))
    check.line(to: CGPoint(x: 485, y: 425))
    check.line(to: CGPoint(x: 640, y: 620))
    check.lineWidth = 62
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor(red: 0.05, green: 0.14, blue: 0.20, alpha: 1).setStroke()
    check.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = "icon_\(base)x\(base)\(factor == 2 ? "@2x" : "").png"
        try render(size: base * factor).write(to: folder.appendingPathComponent(name))
    }
}
