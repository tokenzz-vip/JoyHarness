import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let scale = CGFloat(pixels) / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)
    let base = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 204, yRadius: 204)
    NSColor(calibratedWhite: 0.12, alpha: 1).setFill(); base.fill()
    for (x, color) in [(CGFloat(226), NSColor(calibratedRed: 0.12, green: 0.66, blue: 0.79, alpha: 1)),
                        (CGFloat(546), NSColor(calibratedRed: 0.98, green: 0.38, blue: 0.32, alpha: 1))] {
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 204, width: 252, height: 616), xRadius: 110, yRadius: 110).fill()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: x + 70, y: x < 400 ? 594 : 318, width: 112, height: 112)).fill()
        for (dx, dy) in [(CGFloat(0), CGFloat(46)), (-46, 0), (46, 0), (0, -46)] {
            NSBezierPath(ovalIn: NSRect(x: x + 104 + dx, y: (x < 400 ? 362 : 648) + dy, width: 44, height: 44)).fill()
        }
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = rep.representation(using: .png, properties: [:])!
    if pixels <= 512 { try data.write(to: output.appendingPathComponent("icon_\(pixels)x\(pixels).png")) }
    if pixels >= 32 { try data.write(to: output.appendingPathComponent("icon_\(pixels/2)x\(pixels/2)@2x.png")) }
}
