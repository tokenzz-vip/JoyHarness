import AppKit

/// Finder, Dock and About use the same packaged brand asset.
@MainActor
enum BrandAssets {
    static let applicationIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "JoyHarness", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "JoyHarness")!
    }()

    /// The regular menu bar icon keeps the original monochrome JoyHarness mark.
    static let menuBarIcon = makeMenuBarIcon(colored: false)

    /// The mouse-mode icon keeps the same mark and uses the application's logo colors.
    static let mouseMenuBarIcon = makeMenuBarIcon(colored: true)

    private static func makeMenuBarIcon(colored: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
            // Use the colors from the packaged small-format logo.
            let bubbleColor = colored ? NSColor(srgbRed: 182 / 255, green: 168 / 255, blue: 239 / 255, alpha: 1) : .black
            let leftColor = colored ? NSColor(srgbRed: 25 / 255, green: 199 / 255, blue: 233 / 255, alpha: 1) : .black
            let rightColor = colored ? NSColor(srgbRed: 1, green: 99 / 255, blue: 117 / 255, alpha: 1) : .black

            bubbleColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 9, y: 2, width: 14, height: 11), xRadius: 3, yRadius: 3).fill()
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 10, y: 11)); tail.line(to: NSPoint(x: 9, y: 15))
            tail.line(to: NSPoint(x: 15, y: 11)); tail.close(); tail.fill()

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            let prompt = NSBezierPath()
            prompt.move(to: NSPoint(x: 14, y: 5)); prompt.line(to: NSPoint(x: 16, y: 7))
            prompt.line(to: NSPoint(x: 14, y: 9))
            prompt.move(to: NSPoint(x: 18.5, y: 9)); prompt.line(to: NSPoint(x: 20.5, y: 9))
            prompt.lineWidth = 1.4; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round; prompt.stroke()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: 9, yBy: 15); transform.rotate(byDegrees: 24); transform.concat()
            let left = NSBezierPath(roundedRect: NSRect(x: -6.3, y: -7.2, width: 5.6, height: 14.4), xRadius: 2.5, yRadius: 2.5)
            let right = NSBezierPath(roundedRect: NSRect(x: 0.8, y: -7.2, width: 5.6, height: 14.4), xRadius: 2.5, yRadius: 2.5)
            NSGraphicsContext.current?.compositingOperation = .clear
            for path in [left, right] { path.lineWidth = 1.6; path.stroke() }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            leftColor.setFill(); left.fill()
            rightColor.setFill(); right.fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: -4.9, y: -4.7, width: 2.8, height: 2.8)).fill()
            NSBezierPath(ovalIn: NSRect(x: 2.2, y: 0.8, width: 2.8, height: 2.8)).fill()
            for (x, y) in [(3.6, -5.0), (2.2, -3.6), (5.0, -3.6), (3.6, -2.2)] {
                NSBezierPath(ovalIn: NSRect(x: x - 0.55, y: y - 0.55, width: 1.1, height: 1.1)).fill()
            }
            NSBezierPath(rect: NSRect(x: -4.9, y: 1.6, width: 2.8, height: 0.9)).fill()
            NSBezierPath(rect: NSRect(x: -3.95, y: 0.65, width: 0.9, height: 2.8)).fill()
            NSGraphicsContext.restoreGraphicsState()

            leftColor.setStroke()
            let signal = NSBezierPath()
            signal.move(to: NSPoint(x: 2, y: 4)); signal.curve(to: NSPoint(x: 7, y: 5.5), controlPoint1: NSPoint(x: 4, y: 3.5), controlPoint2: NSPoint(x: 6, y: 4.5))
            signal.lineWidth = 1.4; signal.lineCapStyle = .round; signal.stroke()
            return true
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = !colored
        image.accessibilityDescription = colored ? "JoyHarness · 鼠标模式" : "JoyHarness"
        return image
    }
}
