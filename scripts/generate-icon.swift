#!/usr/bin/env swift
// generate-icon.swift — koe! アプリアイコン & メニューバーアイコン生成
//
// Usage:
//   swift generate-icon.swift app    <output-png>     -- 1024x1024 アプリアイコン
//   swift generate-icon.swift menu   <output-png>     -- メニューバーテンプレート (44x44)
//   swift generate-icon.swift menu1x <output-png>     -- メニューバーテンプレート (22x22)

import AppKit

guard CommandLine.arguments.count > 2 else {
    fputs("Usage: swift generate-icon.swift <app|menu|menu1x> <output-png>\n", stderr)
    exit(1)
}

let mode = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func makeBitmap(width: Int, height: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

/// Render an SF Symbol as a tinted NSImage
func sfSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!

    let size = base.size
    let img = NSImage(size: size, flipped: false) { rect in
        base.draw(in: rect)
        color.set()
        rect.fill(using: .sourceIn)
        return true
    }
    return img
}

/// Draw a bold "!" character
func drawExclamation(in ctx: CGContext, center: CGPoint, fontSize: CGFloat, color: NSColor) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
    let str = NSAttributedString(string: "!", attributes: [
        .font: font,
        .foregroundColor: color,
    ])
    let line = CTLineCreateWithAttributedString(str)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

    let x = center.x - bounds.width / 2 - bounds.origin.x
    let y = center.y - bounds.height / 2 - bounds.origin.y

    ctx.saveGState()
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// ---------------------------------------------------------------------------
// App icon (1024x1024)
// ---------------------------------------------------------------------------

func generateAppIcon(outputPath: String) {
    let s: CGFloat = 1024
    let rep = makeBitmap(width: Int(s), height: Int(s))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // --- Rounded rect background ---
    let corner: CGFloat = s * 0.22
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Background: flat #fbefb3
    ctx.setFillColor(CGColor(red: 0.984, green: 0.937, blue: 0.702, alpha: 1.0))
    ctx.fill(bgRect)

    // --- Draw SF Symbol mic.fill (large, centered) with drop shadow ---
    // Mic color: #abc7f9
    let micColor = NSColor(red: 0.671, green: 0.780, blue: 0.976, alpha: 1.0)
    let mic = sfSymbol("mic.fill", pointSize: s * 0.58, weight: .medium, color: micColor)
    let micSize = mic.size
    let micX = s * 0.50 - micSize.width / 2
    let micY = s * 0.46 - micSize.height / 2
    let micRect = NSRect(x: micX, y: micY, width: micSize.width, height: micSize.height)

    // Shadow for mic
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.25))
    mic.draw(in: micRect)
    ctx.restoreGState()

    // --- Draw "!" badge (orange #fab24e, top-right) with drop shadow ---
    let exColor = NSColor(red: 0.980, green: 0.698, blue: 0.306, alpha: 1.0)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.025,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.20))
    drawExclamation(in: ctx, center: CGPoint(x: s * 0.74, y: s * 0.74), fontSize: s * 0.30, color: exColor)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    savePNG(rep, to: outputPath)
    print("App icon generated: \(outputPath)")
}

// ---------------------------------------------------------------------------
// Menu bar template icon (mic + !)
// ---------------------------------------------------------------------------

func generateMenuBarIcon(outputPath: String, scale: Int) {
    let s = 22 * scale
    let sz = CGFloat(s)
    let rep = makeBitmap(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let black = NSColor(red: 0, green: 0, blue: 0, alpha: 0.85)

    // SF Symbol mic.fill (centered, large)
    let mic = sfSymbol("mic.fill", pointSize: sz * 0.58, weight: .medium, color: black)
    let micSize = mic.size
    let micX = sz * 0.42 - micSize.width / 2
    let micY = sz * 0.46 - micSize.height / 2
    mic.draw(in: NSRect(x: micX, y: micY, width: micSize.width, height: micSize.height))

    // "!" badge (top-right, smaller)
    drawExclamation(in: ctx, center: CGPoint(x: sz * 0.78, y: sz * 0.74), fontSize: sz * 0.38, color: black)

    NSGraphicsContext.restoreGraphicsState()
    savePNG(rep, to: outputPath)
    print("Menu bar icon generated (\(scale)x): \(outputPath)")
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

switch mode {
case "app":
    generateAppIcon(outputPath: outputPath)
case "menu":
    generateMenuBarIcon(outputPath: outputPath, scale: 2)
case "menu1x":
    generateMenuBarIcon(outputPath: outputPath, scale: 1)
default:
    fputs("Unknown mode: \(mode). Use 'app', 'menu', or 'menu1x'.\n", stderr)
    exit(1)
}
