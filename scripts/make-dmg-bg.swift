#!/usr/bin/swift
// Generates a minimal dark background PNG for the Slapppy DMG installer window.
// Usage: swift scripts/make-dmg-bg.swift [output-path]
import AppKit

let W: CGFloat = 660, H: CGFloat = 400

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(W), pixelsHigh: Int(H),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// ── Background ──────────────────────────────────────────────────────
NSColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1).setFill()
NSBezierPath.fill(NSRect(x: 0, y: 0, width: W, height: H))

// ── Arrow (app icon at ~165,185 → Applications at ~495,185) ─────────
let arrowY: CGFloat  = 185
let shaftX0: CGFloat = 245   // right edge of left icon area
let shaftX1: CGFloat = 400   // left edge of arrowhead
let headEnd: CGFloat = 420
let headW: CGFloat   = 11

let ink = NSColor.white.withAlphaComponent(0.22)

// shaft
let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: shaftX0, y: arrowY))
shaft.line(to: NSPoint(x: shaftX1, y: arrowY))
shaft.lineWidth = 2
shaft.lineCapStyle = .round
ink.setStroke()
shaft.stroke()

// arrowhead (filled triangle)
let head = NSBezierPath()
head.move(to: NSPoint(x: headEnd, y: arrowY))
head.line(to: NSPoint(x: shaftX1, y: arrowY + headW))
head.line(to: NSPoint(x: shaftX1, y: arrowY - headW))
head.close()
ink.setFill()
head.fill()

// ── Label ────────────────────────────────────────────────────────────
let paraStyle = NSMutableParagraphStyle()
paraStyle.alignment = .center

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .regular),
    .foregroundColor: NSColor.white.withAlphaComponent(0.28),
    .paragraphStyle: paraStyle
]
("Drag to Applications" as NSString).draw(
    in: CGRect(x: (W - 200) / 2, y: arrowY - 34, width: 200, height: 18),
    withAttributes: attrs
)

NSGraphicsContext.restoreGraphicsState()

// ── Write PNG ─────────────────────────────────────────────────────────
let dest = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "scripts/dmg-background.png"

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: dest))
print("✓  Background written to \(dest)")
