import AppKit
import Foundation

// Package existing Bubble Tax artwork as a native macOS icon; no generated
// replacement artwork or network access is required.
let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = project.appendingPathComponent("Sources/BubbleTaxBar/Resources")
guard let artwork = NSImage(contentsOf: resources.appendingPathComponent("Personas/bubbleSponsor.png")) else {
    fatalError("Missing Bubble Tax artwork")
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("bubble-tax-icon-" + UUID().uuidString)
let iconset = temporary.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func png(size: Int) -> Data {
    let side = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: side / 1024, y: side / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    // Preserve the full character and speech-free bubble inside the icon tile.
    let bounds = NSRect(x: 148, y: 148, width: 728, height: 728)
    let scale = min(bounds.width / artwork.size.width, bounds.height / artwork.size.height)
    let dimensions = NSSize(width: artwork.size.width * scale, height: artwork.size.height * scale)
    let destination = NSRect(x: bounds.midX - dimensions.width / 2, y: bounds.midY - dimensions.height / 2,
        width: dimensions.width, height: dimensions.height)
    artwork.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try png(size: points * scale).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
let previews = project.appendingPathComponent("docs/images")
try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
try png(size: 1024).write(to: previews.appendingPathComponent("app-icon.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("Could not package the app icon") }
print("Created AppIcon.icns and docs/images/app-icon.png")
