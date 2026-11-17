import AppKit

public final class CursorFactory {

    /// Spotlight cross: 3x3 pixel plus sign, slightly transparent, in the pen colour.
    static let spotlightCrossAlpha: CGFloat = 0.8

    /// Pen cursor: a filled dot in the pen colour whose diameter is the pen stroke width,
    /// with a hairline dark rim so it stays visible over ink of the same colour.
    public static func makePenCursor(penWidth: CGFloat = 4.0, color: NSColor = Stroke.defaultColor) -> NSCursor {
        let radius = max(penWidth / 2.0, 1.5)
        let dimension = ceil(radius * 2.0 + 4.0)
        let size = NSSize(width: dimension, height: dimension)
        let center = CGPoint(x: dimension / 2.0, y: dimension / 2.0)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(true)
            let dot = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2.0, height: radius * 2.0)

            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: dot)

            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(0.75)
            ctx.strokeEllipse(in: dot.insetBy(dx: -0.375, dy: -0.375))
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: center.x, y: center.y))
    }

    /// Spotlight cursor: a pixelated 3x3 plus sign marking the spotlight centre.
    /// Built from bitmaps (1x and 2x) so every "pixel" stays a hard-edged square on any display.
    public static func makeSpotlightCursor(color: NSColor = Stroke.defaultColor) -> NSCursor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let alpha = spotlightCrossAlpha
        let cross: [(Int, Int)] = [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)]

        let image = NSImage(size: NSSize(width: 3, height: 3))
        for scale in [1, 2] {
            let side = 3 * scale
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: side,
                pixelsHigh: side,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { continue }
            rep.size = NSSize(width: 3, height: 3)
            let pixel = NSColor(
                deviceRed: rgb.redComponent,
                green: rgb.greenComponent,
                blue: rgb.blueComponent,
                alpha: alpha
            )
            for (cx, cy) in cross {
                for dx in 0..<scale {
                    for dy in 0..<scale {
                        rep.setColor(pixel, atX: cx * scale + dx, y: cy * scale + dy)
                    }
                }
            }
            image.addRepresentation(rep)
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 1.5, y: 1.5))
    }
}
