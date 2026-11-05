import AppKit
import CoreGraphics

public enum DrawingGeometry {
    
    @inlinable
    public static func midPoint(_ p1: CGPoint, _ p2: CGPoint) -> CGPoint {
        return CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
    }
    
    @inlinable
    public static func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    public static func buildSmoothPath(from points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        
        if points.count == 1 {
            path.addArc(center: first, radius: 1.0, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            return path
        }
        
        if points.count == 2 {
            path.move(to: first)
            path.addLine(to: points[1])
            return path
        }
        
        path.move(to: first)
        let firstMid = midPoint(points[0], points[1])
        path.addLine(to: firstMid)
        
        for i in 1..<(points.count - 1) {
            let nextMid = midPoint(points[i], points[i + 1])
            path.addQuadCurve(to: nextMid, control: points[i])
        }
        
        path.addLine(to: points.last!)
        return path
    }
    
    /// Radial gradient for punching a circular spotlight out of a darker overlay using .destinationOut:
    /// Center (0.0): 1.0 alpha (full punch -> 100% transparent hole).
    /// Perimeter (1.0): 0.0 alpha (no punch -> darker scrim remains).
    public static func createSpotlightPunchGradient() -> CGGradient? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let colors = [
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.88),
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.55),
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.18),
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        ] as CFArray
        
        let locations: [CGFloat] = [0.0, 0.35, 0.65, 0.88, 1.0]
        return CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)
    }
    
    public static func clampRadius(_ radius: CGFloat, min: CGFloat = 40.0, max: CGFloat = 400.0) -> CGFloat {
        return Swift.min(Swift.max(radius, min), max)
    }
}
