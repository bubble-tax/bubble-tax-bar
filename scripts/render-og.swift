// Render the share card from native typography and the existing comic asset.
// Run from the repository root: swift scripts/render-og.swift
import AppKit

let width = 1200, height = 630
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let paper = NSColor(srgbRed: 247/255, green: 246/255, blue: 242/255, alpha: 1)
let ink = NSColor(srgbRed: 23/255, green: 23/255, blue: 23/255, alpha: 1)
let muted = NSColor(srgbRed: 105/255, green: 104/255, blue: 100/255, alpha: 1)
paper.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

func text(_ value: String, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat,
          size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = ink) {
    (value as NSString).draw(in: NSRect(x: x, y: 630 - top - height, width: width, height: height),
        withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
text("Bubble Tax", x: 64, top: 55, width: 700, height: 55, size: 36, weight: .bold)
text("Stop sponsoring", x: 64, top: 190, width: 740, height: 100, size: 76, weight: .bold)
text("the AI bubble.", x: 64, top: 275, width: 740, height: 100, size: 76, weight: .bold)
text("Unused quota. Smaller plans. Less money burned.", x: 64, top: 399,
     width: 740, height: 44, size: 25, color: muted)
text("A Mac menu-bar app for AI subscriptions.", x: 64, top: 535,
     width: 950, height: 40, size: 22, color: muted)

let mascot = NSImage(contentsOfFile: "site/assets/bubbleSponsor.png")!
mascot.draw(in: NSRect(x: 820, y: 150, width: 320, height: 320),
            from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: "site/assets/bubble-tax-og.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
print("Rendered \(output.path) (1200 × 630)")
