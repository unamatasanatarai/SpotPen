import AppKit

public enum AnnotationTool: String, CaseIterable {
    case pen = "Pen"
    case spotlight = "Spotlight"
}

public struct Stroke: Equatable {
    public let id: UUID
    public var points: [CGPoint]
    public var color: NSColor
    public var lineWidth: CGFloat
    
    public init(
        id: UUID = UUID(),
        points: [CGPoint] = [],
        color: NSColor = Stroke.defaultColor,
        lineWidth: CGFloat = 4.0
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
    }
    
    /// Area this stroke paints, including round caps and shadow.
    public var inkRect: CGRect {
        return DrawingGeometry.inkRect(of: points, lineWidth: lineWidth)
    }
    
    // Only one single pen color across the application (10% transparent -> 0.90 alpha)
    public static let defaultColor = NSColor(red: 1.0, green: 0.22, blue: 0.28, alpha: 0.90)
    
    // Slight shadow under pen strokes for enhanced depth and contrast
    public static let shadowOffset = CGSize(width: 0.0, height: -1.5)
    public static let shadowBlur: CGFloat = 3.5
    public static let shadowColor = CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.35)
}

