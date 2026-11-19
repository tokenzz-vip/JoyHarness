import AppKit

// Raster sizes are explicit so exports do not depend on the screen's Retina scale.
guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift scripts/generate_icon.swift <output.iconset> [source.png]\n", stderr)
    exit(1)
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let source = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2])
    : root.appendingPathComponent("assets/brand/joyharness-icon.png")
let smallSource = source.deletingLastPathComponent().appendingPathComponent("joyharness-icon-small.png")
guard let image = NSImage(contentsOf: source) else {
    fputs("Cannot read brand source: \(source.path)\n", stderr)
    exit(1)
}
let smallImage = NSImage(contentsOf: smallSource) ?? image
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let representation = points <= 32 ? smallImage : image
        representation.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero,
                   operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
    }
}
