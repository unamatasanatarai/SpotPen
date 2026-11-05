import AppKit

public final class CursorFactory {
    
    /// Pen cursor: a target reticle with an inner circle (exact pen stroke size) and an outer circle (always larger).
    /// Dynamically grows with penWidth.
    public static func makePenCursor(penWidth: CGFloat = 4.0, color: NSColor = Stroke.defaultColor) -> NSCursor {
        let innerRadius = max(penWidth / 2.0, 1.5)
        let outerRadius = innerRadius + max(6.0, innerRadius * 0.35)
        let dimension = max(36.0, ceil((outerRadius + 12.0) * 2.0))
        let size = NSSize(width: dimension, height: dimension)
        let center = CGPoint(x: dimension / 2.0, y: dimension / 2.0)
        
        let image = NSImage(size: size)
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return NSCursor.crosshair
        }
        
        ctx.saveGState()
        ctx.setShouldAntialias(true)
        
        // 1. Outer circle (always larger than inner circle)
        // High contrast dark outline with subtle drop shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0.0, height: -1.2),
            blur: 2.5,
            color: NSColor.black.withAlphaComponent(0.40).cgColor
        )
        ctx.addArc(center: center, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.70).cgColor)
        ctx.setLineWidth(3.0)
        ctx.strokePath()
        ctx.restoreGState()
        
        // Crisp white outer ring
        ctx.addArc(center: center, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        
        // 2. Inner circle (exact pen stroke size: diameter = penWidth)
        // High contrast dark outline
        ctx.addArc(center: center, radius: innerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.70).cgColor)
        ctx.setLineWidth(2.4)
        ctx.strokePath()
        
        // Foreground stroke in pen color representing pen stroke width
        ctx.addArc(center: center, radius: innerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.4)
        ctx.strokePath()
        
        // 3. Target crosshair ticks (left, right, top, bottom) extending outward from outer circle
        let tickInner = outerRadius + 2.0
        let tickOuter = outerRadius + 7.5
        let ticks: [(CGPoint, CGPoint)] = [
            (CGPoint(x: center.x - tickOuter, y: center.y), CGPoint(x: center.x - tickInner, y: center.y)),
            (CGPoint(x: center.x + tickInner, y: center.y), CGPoint(x: center.x + tickOuter, y: center.y)),
            (CGPoint(x: center.x, y: center.y - tickOuter), CGPoint(x: center.x, y: center.y - tickInner)),
            (CGPoint(x: center.x, y: center.y + tickInner), CGPoint(x: center.x, y: center.y + tickOuter))
        ]
        
        // Dark outline for ticks
        ctx.setLineWidth(2.8)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.70).cgColor)
        ctx.setLineCap(.round)
        for (p1, p2) in ticks {
            ctx.move(to: p1)
            ctx.addLine(to: p2)
        }
        ctx.strokePath()
        
        // Crisp white ticks
        ctx.setLineWidth(1.4)
        ctx.setStrokeColor(NSColor.white.cgColor)
        for (p1, p2) in ticks {
            ctx.move(to: p1)
            ctx.addLine(to: p2)
        }
        ctx.strokePath()
        
        // 4. Center precision target dot at hotspot
        ctx.addArc(center: center, radius: 2.2, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.70).cgColor)
        ctx.fillPath()
        
        ctx.addArc(center: center, radius: 1.4, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
        
        ctx.restoreGState()
        image.unlockFocus()
        
        return NSCursor(image: image, hotSpot: NSPoint(x: center.x, y: center.y))
    }
    
    /// Spotlight cursor: focal reticle for the spotlight beam.
    public static func makeSpotlightCursor(radius: CGFloat = 100.0) -> NSCursor {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return NSCursor.crosshair
        }
        
        ctx.saveGState()
        ctx.setShouldAntialias(true)
        let center = CGPoint(x: 16, y: 16)
        
        // Soft outer ring with shadow
        ctx.addArc(center: center, radius: 8.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.50).cgColor)
        ctx.setLineWidth(2.6)
        ctx.strokePath()
        
        ctx.addArc(center: center, radius: 8.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.90).cgColor)
        ctx.setLineWidth(1.4)
        ctx.strokePath()
        
        // Center focal point
        ctx.addArc(center: center, radius: 2.2, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.50).cgColor)
        ctx.fillPath()
        
        ctx.addArc(center: center, radius: 1.4, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        
        ctx.restoreGState()
        image.unlockFocus()
        
        return NSCursor(image: image, hotSpot: NSPoint(x: 16, y: 16))
    }
}
