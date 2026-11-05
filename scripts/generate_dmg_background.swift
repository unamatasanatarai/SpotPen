import AppKit

func generateDMGBackground(scale: CGFloat, outputPath: String) {
    let ptWidth: CGFloat = 660
    let ptHeight: CGFloat = 400
    let pxWidth = Int(ptWidth * scale)
    let pxHeight = Int(ptHeight * scale)
    
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pxWidth,
        pixelsHigh: pxHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: pxWidth * 4,
        bitsPerPixel: 32
    )!
    rep.size = NSSize(width: ptWidth, height: ptHeight)
    
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create NSGraphicsContext")
    }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    
    // Invert coordinate system to match top-left (0,0)
    cg.translateBy(x: 0, y: ptHeight)
    cg.scaleBy(x: 1.0, y: -1.0)
    
    // Palette matching SpotPen AppIcon:
    // Rich midnight obsidian background, golden spotlight gradients, champagne typography
    let bgTop = NSColor(srgbRed: 0.043, green: 0.055, blue: 0.086, alpha: 1.0) // #0B0E16
    let bgBottom = NSColor(srgbRed: 0.075, green: 0.098, blue: 0.149, alpha: 1.0) // #131926
    let goldBright = NSColor(srgbRed: 1.0, green: 0.88, blue: 0.52, alpha: 1.0) // #FFE085
    let goldMid = NSColor(srgbRed: 0.88, green: 0.72, blue: 0.38, alpha: 1.0) // #E0B861
    let goldDeep = NSColor(srgbRed: 0.70, green: 0.52, blue: 0.22, alpha: 1.0) // #B38538
    let champagneText = NSColor(srgbRed: 0.94, green: 0.86, blue: 0.68, alpha: 0.90)
    let secondaryText = NSColor(srgbRed: 0.65, green: 0.70, blue: 0.80, alpha: 0.55)
    
    // 1. Base Midnight Gradient
    let bgGrad = NSGradient(starting: bgTop, ending: bgBottom)!
    bgGrad.draw(in: CGRect(x: 0, y: 0, width: ptWidth, height: ptHeight), angle: 90)
    
    // 2. Ambient Golden Spotlight Glow behind SpotPen app icon (x=180, y=196)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let glowColors = [
        goldBright.withAlphaComponent(0.18).cgColor,
        goldMid.withAlphaComponent(0.10).cgColor,
        goldDeep.withAlphaComponent(0.04).cgColor,
        goldDeep.withAlphaComponent(0.0).cgColor
    ] as CFArray
    let glowLocations: [CGFloat] = [0.0, 0.35, 0.70, 1.0]
    if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: glowLocations) {
        cg.drawRadialGradient(
            glowGrad,
            startCenter: CGPoint(x: 180, y: 196),
            startRadius: 0,
            endCenter: CGPoint(x: 180, y: 196),
            endRadius: 180,
            options: []
        )
    }
    
    // Center ambient light pool
    let centerColors = [
        goldMid.withAlphaComponent(0.09).cgColor,
        goldDeep.withAlphaComponent(0.0).cgColor
    ] as CFArray
    let centerLocations: [CGFloat] = [0.0, 1.0]
    if let centerGrad = CGGradient(colorsSpace: colorSpace, colors: centerColors, locations: centerLocations) {
        cg.drawRadialGradient(
            centerGrad,
            startCenter: CGPoint(x: 330, y: 196),
            startRadius: 0,
            endCenter: CGPoint(x: 330, y: 196),
            endRadius: 130,
            options: []
        )
    }
    
    // 3. Perimeter hairline border
    let border = NSBezierPath(rect: CGRect(x: 0.5, y: 0.5, width: ptWidth - 1, height: ptHeight - 1))
    goldMid.withAlphaComponent(0.18).setStroke()
    border.lineWidth = 1.0
    border.stroke()
    
    // 4. Top subtle gold highlight sheen
    let sheen = NSBezierPath()
    sheen.move(to: CGPoint(x: 1, y: 1))
    sheen.line(to: CGPoint(x: ptWidth - 1, y: 1))
    goldBright.withAlphaComponent(0.40).setStroke()
    sheen.lineWidth = 1.0
    sheen.stroke()
    
    let yCenter: CGFloat = 196
    
    // 5. Spotlight Pedestal Aperture under SpotPen (x=180, y=196)
    let spotPenRing = NSBezierPath(ovalIn: CGRect(x: 180 - 58, y: yCenter - 58, width: 116, height: 116))
    goldMid.withAlphaComponent(0.28).setStroke()
    spotPenRing.lineWidth = 1.4
    spotPenRing.stroke()
    
    let spotPenInner = NSBezierPath(ovalIn: CGRect(x: 180 - 54, y: yCenter - 54, width: 108, height: 108))
    goldBright.withAlphaComponent(0.10).setStroke()
    spotPenInner.lineWidth = 1.0
    spotPenInner.stroke()
    
    // Pedestal Aperture under Applications (x=480, y=196)
    let appRing = NSBezierPath(ovalIn: CGRect(x: 480 - 58, y: yCenter - 58, width: 116, height: 116))
    NSColor(white: 1.0, alpha: 0.12).setStroke()
    appRing.lineWidth = 1.4
    appRing.stroke()
    
    // 6. Dashed golden trajectory guide between the two icon zones
    let track = NSBezierPath()
    track.move(to: CGPoint(x: 248, y: yCenter))
    track.line(to: CGPoint(x: 298, y: yCenter))
    track.move(to: CGPoint(x: 362, y: yCenter))
    track.line(to: CGPoint(x: 412, y: yCenter))
    let pattern: [CGFloat] = [4, 4]
    track.setLineDash(pattern, count: 2, phase: 0)
    track.lineWidth = 1.5
    goldMid.withAlphaComponent(0.45).setStroke()
    track.stroke()
    
    // 7. Floating action capsule badge at the center (x=330, y=196)
    let pillRect = CGRect(x: 330 - 28, y: yCenter - 18, width: 56, height: 36)
    let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 18, yRadius: 18)
    
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: 4),
        blur: 14,
        color: goldMid.withAlphaComponent(0.25).cgColor
    )
    NSColor(srgbRed: 0.065, green: 0.082, blue: 0.125, alpha: 0.95).setFill()
    pillPath.fill()
    cg.restoreGState()
    
    goldMid.withAlphaComponent(0.70).setStroke()
    pillPath.lineWidth = 1.2
    pillPath.stroke()
    
    // 8. Sculpted brilliant gold directional arrow inside capsule
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 319, y: yCenter))
    arrow.line(to: CGPoint(x: 341, y: yCenter))
    arrow.move(to: CGPoint(x: 334, y: yCenter - 5.5))
    arrow.line(to: CGPoint(x: 341, y: yCenter))
    arrow.line(to: CGPoint(x: 334, y: yCenter + 5.5))
    arrow.lineWidth = 2.4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    goldBright.setStroke()
    arrow.stroke()
    
    // 9. Refined typography matching AppIcon aesthetic
    cg.translateBy(x: 0, y: ptHeight)
    cg.scaleBy(x: 1.0, y: -1.0)
    
    let pStyle = NSMutableParagraphStyle()
    pStyle.alignment = .center
    
    // Top headline: "DRAG TO APPLICATIONS"
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .bold),
        .foregroundColor: champagneText,
        .paragraphStyle: pStyle,
        .kern: 2.2
    ]
    let titleStr = NSAttributedString(string: "DRAG TO APPLICATIONS", attributes: titleAttrs)
    titleStr.draw(in: CGRect(x: 180, y: ptHeight - 52, width: 300, height: 18))
    
    // Bottom feature subtitle: "Hold Shift for Spotlight • Screen Pen Anytime"
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        .foregroundColor: secondaryText,
        .paragraphStyle: pStyle,
        .kern: 1.2
    ]
    let subStr = NSAttributedString(string: "Hold Shift for Spotlight  •  Screen Pen Anytime", attributes: subAttrs)
    subStr.draw(in: CGRect(x: 130, y: 46, width: 400, height: 16))
    
    NSGraphicsContext.restoreGraphicsState()
    
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to convert image to PNG")
    }
    try! pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Generated: \(outputPath) (\(pxWidth)x\(pxHeight))")
}

generateDMGBackground(scale: 1.0, outputPath: "Resources/dmg_background.png")
generateDMGBackground(scale: 2.0, outputPath: "Resources/dmg_background@2x.png")
