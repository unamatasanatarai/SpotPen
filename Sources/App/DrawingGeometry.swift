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

    /// Smallest rectangle containing all points (`.null` when empty).
    public static func boundingRect<C: Collection>(of points: C) -> CGRect where C.Element == CGPoint {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// How far ink (round caps, the single-point dot, and the drop shadow) can extend beyond a stroke's points.
    public static func strokeInkPadding(lineWidth: CGFloat) -> CGFloat {
        let shadowReach = Stroke.shadowBlur * 2.0 + Swift.max(abs(Stroke.shadowOffset.width), abs(Stroke.shadowOffset.height))
        return lineWidth / 2.0 + 1.0 + shadowReach + 2.0
    }

    /// Area a stroke made of `points` may paint, including caps and shadow.
    public static func inkRect<C: Collection>(of points: C, lineWidth: CGFloat) -> CGRect where C.Element == CGPoint {
        let rect = boundingRect(of: points)
        guard !rect.isNull else { return .null }
        let pad = strokeInkPadding(lineWidth: lineWidth)
        return rect.insetBy(dx: -pad, dy: -pad)
    }

    /// Area covered by the spotlight aperture centred at `center`.
    public static func spotlightRect(center: CGPoint, radius: CGFloat) -> CGRect {
        let r = radius + 2.0
        return CGRect(x: center.x - r, y: center.y - r, width: r * 2.0, height: r * 2.0)
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

/// Strokes pen ink with the app-wide style. Shared by on-screen drawing and the committed-stroke cache
/// so both look identical.
enum StrokeRenderer {
    /// `shadowScale` converts the point-based shadow to the context's base space. CoreGraphics applies
    /// shadow offset/blur in base space, ignoring the CTM, so an offscreen bitmap drawn at 2x needs 2.
    static func stroke(points: [CGPoint], color: CGColor, lineWidth: CGFloat, in ctx: CGContext, shadowScale: CGFloat) {
        guard !points.isEmpty else { return }
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShadow(
            offset: CGSize(width: Stroke.shadowOffset.width * shadowScale, height: Stroke.shadowOffset.height * shadowScale),
            blur: Stroke.shadowBlur * shadowScale,
            color: Stroke.shadowColor
        )
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.addPath(DrawingGeometry.buildSmoothPath(from: points))
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func stroke(_ stroke: Stroke, in ctx: CGContext, shadowScale: CGFloat) {
        self.stroke(points: stroke.points, color: stroke.color.cgColor, lineWidth: stroke.lineWidth, in: ctx, shadowScale: shadowScale)
    }
}

/// Bitmap holding all committed strokes, so a frame only blits pixels instead of re-stroking every
/// path with a shadow. New strokes are drawn into it incrementally; it is fully rebuilt only on
/// clear/resize/scale change.
final class StrokeRenderCache {
    /// Pixel buffer shared by the drawing context and the images handed to `draw(_:)`.
    /// Images reference it without copying; the data provider keeps it alive while any image exists.
    private final class PixelBuffer {
        let bytes: UnsafeMutableRawPointer
        let count: Int
        
        init?(count: Int) {
            guard let bytes = calloc(count, 1) else { return nil }
            self.bytes = bytes
            self.count = count
        }
        
        deinit {
            free(bytes)
        }
    }
    
    let pointSize: CGSize
    let scale: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
    private let bytesPerRow: Int
    private let colorSpace: CGColorSpace
    private let buffer: PixelBuffer
    private let context: CGContext
    private static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    
    init?(pointSize: CGSize, scale: CGFloat, colorSpace: CGColorSpace) {
        let width = Int((pointSize.width * scale).rounded(.up))
        let height = Int((pointSize.height * scale).rounded(.up))
        guard width > 0, height > 0, scale > 0 else { return nil }
        let bytesPerRow = width * 4
        guard let buffer = PixelBuffer(count: bytesPerRow * height),
              let ctx = CGContext(
                data: buffer.bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: Self.bitmapInfo
              ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setShouldAntialias(true)
        self.pointSize = pointSize
        self.scale = scale
        self.pixelWidth = width
        self.pixelHeight = height
        self.bytesPerRow = bytesPerRow
        self.colorSpace = colorSpace
        self.buffer = buffer
        self.context = ctx
    }
    
    func matches(pointSize: CGSize, scale: CGFloat) -> Bool {
        return self.pointSize == pointSize && self.scale == scale
    }
    
    /// Rect (in points) that the cached image covers.
    var drawRect: CGRect {
        return CGRect(x: 0, y: 0, width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
    }
    
    func draw(_ stroke: Stroke) {
        StrokeRenderer.stroke(stroke, in: context, shadowScale: scale)
    }
    
    /// A zero-copy image of the current pixels. `CGBitmapContext.makeImage()` would map a second,
    /// copy-on-write bitmap (another ~20 MB at 2880x1800) that CoreGraphics keeps alive. Create a
    /// fresh image for each draw and do not keep it: its pixels change with the next stroke.
    func image() -> CGImage? {
        let retained = Unmanaged.passRetained(buffer)
        guard let provider = CGDataProvider(
            dataInfo: retained.toOpaque(),
            data: buffer.bytes,
            size: buffer.count,
            releaseData: { info, _, _ in
                if let info = info {
                    Unmanaged<PixelBuffer>.fromOpaque(info).release()
                }
            }
        ) else {
            retained.release()
            return nil
        }
        return CGImage(
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
