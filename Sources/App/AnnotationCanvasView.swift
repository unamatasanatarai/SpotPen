import AppKit
import CoreGraphics

public protocol AnnotationCanvasDelegate: AnyObject {
    func canvasDidRequestClose()
}

public final class AnnotationCanvasView: NSView {
    public weak var delegate: AnnotationCanvasDelegate?

    public static let penWidthRange: ClosedRange<CGFloat> = 1.0...40.0
    public static let spotlightRadiusRange: ClosedRange<CGFloat> = 40.0...400.0
    private static let scrimColor = CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.72)
    private static let spotlightCursor = CursorFactory.makeSpotlightCursor()
    /// Scroll step for a classic mouse wheel line; trackpads report precise point deltas instead.
    private static let wheelLineInPoints: CGFloat = 10.0
    /// Pen width / spotlight radius change per point scrolled. Both tools resize together.
    private static let penWidthPerScrollPoint: CGFloat = 0.04
    private static let spotlightRadiusPerScrollPoint: CGFloat = 0.25

    // Tools & Single Pen Color ("hold shift for spotlight, otherwise it's a pen all the time")
    public private(set) var currentTool: AnnotationTool = .pen {
        didSet {
            guard oldValue != currentTool else { return }
            updateCursor()
            needsDisplay = true
        }
    }

    public let penColor: NSColor = Stroke.defaultColor
    public var penWidth: CGFloat = 4.0 {
        didSet {
            penWidth = min(max(penWidth, Self.penWidthRange.lowerBound), Self.penWidthRange.upperBound)
            if penWidth != oldValue { updateCursor() }
        }
    }

    // Spotlight State (about 100px circle gradiented to transparency)
    public var spotlightPoint: CGPoint = .zero {
        didSet { invalidateSpotlight(from: oldValue, radius: spotlightRadius) }
    }
    public var spotlightRadius: CGFloat = 100.0 {
        didSet {
            spotlightRadius = DrawingGeometry.clampRadius(
                spotlightRadius,
                min: Self.spotlightRadiusRange.lowerBound,
                max: Self.spotlightRadiusRange.upperBound
            )
            invalidateSpotlight(from: spotlightPoint, radius: oldValue)
        }
    }
    private var spotlightPunchGradient: CGGradient? = DrawingGeometry.createSpotlightPunchGradient()

    // Stroke Storage (no history: Esc wipes everything)
    public private(set) var strokes: [Stroke] = []
    private var currentStrokePoints: [CGPoint] = []
    private var renderCache: StrokeRenderCache?

    // Tracking Area & Cursors
    private var trackingArea: NSTrackingArea?
    private var penCursor: NSCursor?
    private var penCursorKey: CGFloat = -1

    public override var acceptsFirstResponder: Bool {
        return true
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    // MARK: - State

    // MARK: - State

    /// Frees the committed-stroke bitmap (tens of MB on Retina displays) while the overlay is hidden.
    /// It is rebuilt from `strokes` on the next draw.
    public func releaseRenderCache() {
        renderCache = nil
    }

    private func invalidateRenderCache() {
        renderCache = nil
        needsDisplay = true
    }

    public override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { invalidateRenderCache() }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        invalidateRenderCache()
    }

    // MARK: - Cursor

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseMoved,
            .mouseEnteredAndExited,
            .cursorUpdate
        ]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    /// Cursor for the active tool. The pen cursor is re-rendered only when the pen width moves
    /// by at least half a point; the spotlight cursor is built once.
    var activeCursor: NSCursor {
        switch currentTool {
        case .spotlight:
            return Self.spotlightCursor
        case .pen:
            let key = (penWidth * 2.0).rounded() / 2.0
            if let cursor = penCursor, key == penCursorKey {
                return cursor
            }
            let cursor = CursorFactory.makePenCursor(penWidth: key, color: penColor)
            penCursor = cursor
            penCursorKey = key
            return cursor
        }
    }

    public func updateCursor() {
        guard let currentWindow = window else { return }
        currentWindow.invalidateCursorRects(for: self)
        let viewPoint = convert(currentWindow.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(viewPoint) {
            activeCursor.set()
        }
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: activeCursor)
    }

    /// Only sets the cursor. cursorUpdate events carry empty modifier flags, and switching tools
    /// itself triggers one, so reading Shift here would immediately undo every switch to spotlight.
    public override func cursorUpdate(with event: NSEvent) {
        activeCursor.set()
    }

    // MARK: - Shift Key Tracking
    //
    // Shift state comes from the events the overlay already receives: flagsChanged while it is key,
    // and the modifier flags carried by every mouse event. No polling, global event monitors,
    // or Accessibility/Input Monitoring permission are needed.

    /// Syncs tool, spotlight position, and cursor with the live keyboard/mouse state; call when the overlay appears.
    public func prepareForPresentation() {
        updateSpotlightPointToCurrentMouse()
        checkShiftModifier()
        updateCursor()
        needsDisplay = true
    }

    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        checkShiftModifier(event.modifierFlags)
    }

    /// Switches between pen and spotlight. Uses `flags` when given, otherwise the current modifier state.
    public func checkShiftModifier(_ flags: NSEvent.ModifierFlags? = nil) {
        let isShiftDown = (flags ?? NSEvent.modifierFlags).contains(.shift)
        let targetTool: AnnotationTool = isShiftDown ? .spotlight : .pen
        guard targetTool != currentTool else { return }

        if currentTool == .pen {
            commitCurrentStroke()
        }
        if targetTool == .spotlight {
            updateSpotlightPointToCurrentMouse()
        }
        currentTool = targetTool
    }

    private func updateSpotlightPointToCurrentMouse() {
        guard let win = window else { return }
        let winLoc = win.convertPoint(fromScreen: NSEvent.mouseLocation)
        spotlightPoint = convert(winLoc, from: nil)
    }

    private func invalidateSpotlight(from oldPoint: CGPoint, radius oldRadius: CGFloat) {
        guard currentTool == .spotlight,
              oldPoint != spotlightPoint || oldRadius != spotlightRadius else { return }
        setNeedsDisplay(DrawingGeometry.spotlightRect(center: oldPoint, radius: oldRadius))
        setNeedsDisplay(DrawingGeometry.spotlightRect(center: spotlightPoint, radius: spotlightRadius))
    }

    // MARK: - Drawing Engine

    /// Test hook: forces the cache scale when the view is rendered outside a window.
    var backingScaleOverride: CGFloat?
    
    private var backingScale: CGFloat {
        return backingScaleOverride ?? window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
    }

    private var cacheColorSpace: CGColorSpace {
        if let space = window?.colorSpace?.cgColorSpace, space.model == .rgb {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// Image of all committed strokes, rebuilding the cache if it is missing or stale.
    func committedStrokesImage() -> (CGImage, CGRect)? {
        guard !strokes.isEmpty else { return nil }
        let scale = backingScale
        if renderCache?.matches(pointSize: bounds.size, scale: scale) != true {
            renderCache = StrokeRenderCache(pointSize: bounds.size, scale: scale, colorSpace: cacheColorSpace)
            strokes.forEach { renderCache?.draw($0) }
        }
        guard let cache = renderCache, let image = cache.image() else { return nil }
        return (image, cache.drawRect)
    }

    /// Draws only `dirtyRect`. AppKit clips the context to the invalidated regions, so a pen drag
    /// or spotlight move costs roughly the size of the changed area, not the whole screen.
    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Clear to guarantee a transparent background and erase the previous spotlight frame.
        ctx.clear(dirtyRect)

        // 2. Spotlight scrim with a gradient aperture at the cursor.
        if currentTool == .spotlight {
            drawSpotlight(in: ctx, rect: dirtyRect)
        }

        // 3. Committed strokes (on top of the spotlight scrim), blitted from the cache.
        if let (image, rect) = committedStrokesImage() {
            ctx.draw(image, in: rect)
        }

        // 4. In-progress stroke, with the same shadow.
        if currentTool == .pen && !currentStrokePoints.isEmpty {
            StrokeRenderer.stroke(points: currentStrokePoints, color: penColor.cgColor, lineWidth: penWidth, in: ctx, shadowScale: 1.0)
        }
    }

    private func drawSpotlight(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()

        // 1. Darken with the scrim.
        ctx.setBlendMode(.normal)
        ctx.setFillColor(Self.scrimColor)
        ctx.fill(rect)

        // 2. Punch the circular aperture, gradiented to transparency.
        if let gradient = spotlightPunchGradient {
            ctx.setBlendMode(.destinationOut)
            ctx.drawRadialGradient(
                gradient,
                startCenter: spotlightPoint,
                startRadius: 0.0,
                endCenter: spotlightPoint,
                endRadius: spotlightRadius,
                options: []
            )
        }

        ctx.restoreGState()
    }

    // MARK: - Mouse Event Handling

    public override func mouseMoved(with event: NSEvent) {
        checkShiftModifier(event.modifierFlags)
        if currentTool == .spotlight {
            spotlightPoint = convert(event.locationInWindow, from: nil)
        }
    }

    public override func mouseDown(with event: NSEvent) {
        checkShiftModifier(event.modifierFlags)
        let point = convert(event.locationInWindow, from: nil)

        switch currentTool {
        case .pen:
            currentStrokePoints = [point]
            invalidateActiveStrokeTail()
        case .spotlight:
            spotlightPoint = point
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        checkShiftModifier(event.modifierFlags)
        let point = convert(event.locationInWindow, from: nil)

        switch currentTool {
        case .pen:
            guard point != currentStrokePoints.last else { return }
            currentStrokePoints.append(point)
            invalidateActiveStrokeTail()
        case .spotlight:
            spotlightPoint = point
        }
    }

    public override func mouseUp(with event: NSEvent) {
        if currentTool == .pen {
            commitCurrentStroke()
        }
    }

    /// Appending a point only changes the path between the last three points
    /// (the previous end segment becomes a curve plus a new end segment).
    private func invalidateActiveStrokeTail() {
        let rect = DrawingGeometry.inkRect(of: currentStrokePoints.suffix(3), lineWidth: penWidth)
        if !rect.isNull { setNeedsDisplay(rect) }
    }

    private func commitCurrentStroke() {
        guard !currentStrokePoints.isEmpty else { return }
        let completedStroke = Stroke(
            points: currentStrokePoints,
            color: penColor,
            lineWidth: penWidth
        )
        currentStrokePoints = []
        strokes.append(completedStroke)
        renderCache?.draw(completedStroke)
        let rect = completedStroke.inkRect
        if !rect.isNull { setNeedsDisplay(rect) }
    }

    // MARK: - Size Adjustment (pen and spotlight resize together)

    /// Grows (positive) or shrinks (negative) both the pen and the spotlight by `points` of scroll.
    public func adjustSize(byScrollPoints points: CGFloat) {
        penWidth += points * Self.penWidthPerScrollPoint
        spotlightRadius += points * Self.spotlightRadiusPerScrollPoint
    }

    public override func scrollWheel(with event: NSEvent) {
        // Shift+wheel on a mouse arrives as horizontal scroll, so fall back to the X axis.
        let dy = event.scrollingDeltaY
        let raw = (dy != 0) ? dy : event.scrollingDeltaX
        guard raw != 0 else { return }
        let points = event.hasPreciseScrollingDeltas ? raw : raw * Self.wheelLineInPoints
        // Undo the natural-scrolling inversion so pushing the wheel / fingers away always enlarges.
        adjustSize(byScrollPoints: event.isDirectionInvertedFromDevice ? -points : points)
    }

    // MARK: - Canvas Actions

    /// Wipes every stroke, including one in progress.
    public func clearAll() {
        guard !strokes.isEmpty || !currentStrokePoints.isEmpty else { return }
        strokes = []
        currentStrokePoints = []
        invalidateRenderCache()
    }

    // MARK: - Keyboard Event Handling

    public override func keyDown(with event: NSEvent) {
        // Esc (53): clear everything and close the overlay.
        if event.keyCode == 53 {
            clearAll()
            delegate?.canvasDidRequestClose()
            return
        }

        // C (8): clear the screen and keep drawing. Ignored with ⌘/⌃/⌥ so shortcuts aren't swallowed.
        if event.keyCode == 8, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            clearAll()
            return
        }

        // '[' / ']': resize pen and spotlight together.
        // charactersIgnoringModifiers keeps Shift, so Shift+[ arrives as "{" on most layouts.
        if let chars = event.charactersIgnoringModifiers, ["[", "]", "{", "}"].contains(chars) {
            let direction: CGFloat = (chars == "]" || chars == "}") ? 1.0 : -1.0
            adjustSize(byScrollPoints: 40.0 * direction)
            return
        }

        super.keyDown(with: event)
    }
}
