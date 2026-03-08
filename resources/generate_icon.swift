#!/usr/bin/env swift
// Generates AppIcon.icns for m1ddc-tray
// A monitor icon with brightness/slider bars

import Cocoa

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let scale = size / 512.0
    let s = { (v: CGFloat) -> CGFloat in v * scale }

    // Background: rounded square with gradient
    let bgRect = CGRect(x: s(20), y: s(20), width: s(472), height: s(472))
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: s(90), cornerHeight: s(90), transform: nil)

    // Light gradient background
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bgColors = [
        CGColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0),
        CGColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1.0),
    ]
    let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: bgColors as CFArray,
                                 locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bgGradient,
                           start: CGPoint(x: s(256), y: s(492)),
                           end: CGPoint(x: s(256), y: s(20)),
                           options: [])
    ctx.restoreGState()

    // Monitor body
    let monW = s(320)
    let monH = s(220)
    let monX = (size - monW) / 2
    let monY = s(190)
    let monRect = CGRect(x: monX, y: monY, width: monW, height: monH)
    let monPath = CGPath(roundedRect: monRect, cornerWidth: s(18), cornerHeight: s(18), transform: nil)

    // Monitor bezel
    ctx.saveGState()
    ctx.addPath(monPath)
    ctx.setFillColor(CGColor(red: 0.25, green: 0.27, blue: 0.33, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Screen area (inside bezel)
    let bezel = s(10)
    let screenRect = CGRect(x: monX + bezel, y: monY + bezel + s(4),
                            width: monW - bezel * 2, height: monH - bezel * 2 - s(4))
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: s(6), cornerHeight: s(6), transform: nil)

    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.clip()
    let screenColors = [
        CGColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 1.0),
        CGColor(red: 0.45, green: 0.35, blue: 0.80, alpha: 1.0),
    ]
    let screenGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: screenColors as CFArray,
                                     locations: [0.0, 1.0])!
    ctx.drawLinearGradient(screenGradient,
                           start: CGPoint(x: monX, y: monY + monH),
                           end: CGPoint(x: monX + monW, y: monY),
                           options: [])
    ctx.restoreGState()

    // Monitor stand - neck
    let standW = s(40)
    let standH = s(40)
    let standX = (size - standW) / 2
    let standY = monY - standH
    ctx.setFillColor(CGColor(red: 0.30, green: 0.32, blue: 0.38, alpha: 1.0))
    ctx.fill(CGRect(x: standX, y: standY, width: standW, height: standH))

    // Monitor stand - base
    let baseW = s(120)
    let baseH = s(14)
    let baseX = (size - baseW) / 2
    let baseY = standY - baseH + s(2)
    let basePath = CGPath(roundedRect: CGRect(x: baseX, y: baseY, width: baseW, height: baseH),
                          cornerWidth: s(6), cornerHeight: s(6), transform: nil)
    ctx.addPath(basePath)
    ctx.setFillColor(CGColor(red: 0.30, green: 0.32, blue: 0.38, alpha: 1.0))
    ctx.fillPath()

    // Slider bars on screen (brightness visualization)
    let barX = monX + bezel + s(20)
    let barW = monW - bezel * 2 - s(40)
    let barH = s(14)
    let barSpacing = s(28)
    let barStartY = monY + bezel + s(30)

    // Bar colors (representing brightness/contrast/volume)
    let barFills: [(fill: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.8,  0.95, 0.75, 0.20),  // Brightness - amber/yellow
        (0.55, 0.30, 0.75, 0.95),  // Contrast - cyan
        (0.65, 0.40, 0.85, 0.45),  // Volume - green
    ]

    for (i, bar) in barFills.enumerated() {
        let y = barStartY + CGFloat(i) * barSpacing

        // Track background
        let trackRect = CGRect(x: barX, y: y, width: barW, height: barH)
        let trackPath = CGPath(roundedRect: trackRect, cornerWidth: s(5), cornerHeight: s(5), transform: nil)
        ctx.addPath(trackPath)
        ctx.setFillColor(CGColor(red: 0.0, green: 0.0, blue: 0.1, alpha: 0.15))
        ctx.fillPath()

        // Filled portion
        let fillW = barW * bar.fill
        let fillRect = CGRect(x: barX, y: y, width: fillW, height: barH)
        let fillPath = CGPath(roundedRect: fillRect, cornerWidth: s(5), cornerHeight: s(5), transform: nil)

        ctx.saveGState()
        ctx.addPath(fillPath)
        ctx.clip()
        let fillColors = [
            CGColor(red: bar.r, green: bar.g, blue: bar.b, alpha: 0.9),
            CGColor(red: bar.r * 0.7, green: bar.g * 0.7, blue: bar.b * 0.7, alpha: 0.9),
        ]
        let fillGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: fillColors as CFArray,
                                       locations: [0.0, 1.0])!
        ctx.drawLinearGradient(fillGradient,
                               start: CGPoint(x: barX, y: y + barH),
                               end: CGPoint(x: barX, y: y),
                               options: [])
        ctx.restoreGState()

        // Slider knob
        let knobR = s(9)
        let knobX = barX + fillW
        let knobY = y + barH / 2
        ctx.addEllipse(in: CGRect(x: knobX - knobR, y: knobY - knobR,
                                  width: knobR * 2, height: knobR * 2))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.fillPath()
    }

    // Small "DDC" text at bottom of screen
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s(18), weight: .bold),
        .foregroundColor: NSColor(white: 1.0, alpha: 0.4),
    ]
    let ddcStr = NSAttributedString(string: "DDC", attributes: attrs)
    let ddcSize = ddcStr.size()
    ddcStr.draw(at: NSPoint(x: (size - ddcSize.width) / 2,
                            y: monY + bezel + s(8)))

    image.unlockFocus()
    return image
}

// Generate iconset 
let iconsetPath = "AppIcon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let img = drawIcon(size: entry.size)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(entry.name)")
        continue
    }
    let path = "\(iconsetPath)/\(entry.name).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("Generated \(entry.name).png (\(Int(entry.size))x\(Int(entry.size)))")
}

print("Iconset ready. Run: iconutil -c icns \(iconsetPath)")
