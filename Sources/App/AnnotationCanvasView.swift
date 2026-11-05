import AppKit
import CoreGraphics

public protocol AnnotationCanvasDelegate: AnyObject {
    func canvasDidRequestClose()
}

public final class AnnotationCanvasView: NSView {
    public weak var delegate: AnnotationCanvasDelegate?
    
    // Tools & Single Pen Color
    public private(set) var currentTool: AnnotationTool = .pen {
        didSet {
            updateCursor()
            needsDisplay = true
        }
    }
    
    public let penColor: NSColor = Stroke.defaultColor
    public var penWidth: CGFloat = 4.0
    
    // Spotlight State (about 100px circle gradiented to transparency)
    public var spotlightPoint: CGPoint = .zero
    public var spotlightRadius: CGFloat = 100.0
    private var spotlightPunchGradient: CGGradient?
    
    // Stroke Storage & History
    public private(set) var strokes: [Stroke] = []
    public private(set) var undoStack: [[Stroke]] = []
    private var currentStrokePoints: [CGPoint] = []
    
    // Tracking Area & Cursors
    private var trackingArea: NSTrackingArea?
    private var penCursor: NSCursor?
    private var spotlightCursor: NSCursor?
    
    // Continuous Modifier Monitoring
    private var modifierCheckTimer: Timer?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    
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
    
    deinit {
        stopMonitoringModifiers()
    }
    
    private func setup() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.clear.cgColor
        spotlightPunchGradient = DrawingGeometry.createSpotlightPunchGradient()
        updateCursor()
    }
    
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
    
    public func updateCursor() {
        penCursor = CursorFactory.makePenCursor(penWidth: penWidth, color: penColor)
        spotlightCursor = CursorFactory.makeSpotlightCursor(radius: spotlightRadius)
        
        window?.invalidateCursorRects(for: self)
        
        if let currentWindow = window {
            let mouseLoc = currentWindow.mouseLocationOutsideOfEventStream
            let viewPoint = convert(mouseLoc, from: nil)
            if bounds.contains(viewPoint) {
                let cursor = (currentTool == .pen) ? (penCursor ?? NSCursor.arrow) : (spotlightCursor ?? NSCursor.crosshair)
                cursor.set()
            }
        }
    }
    
    public override func resetCursorRects() {
        super.resetCursorRects()
        let cursor = (currentTool == .pen) ? (penCursor ?? NSCursor.arrow) : (spotlightCursor ?? NSCursor.crosshair)
        addCursorRect(bounds, cursor: cursor)
    }
    
    public override func cursorUpdate(with event: NSEvent) {
        checkShiftModifier(event.modifierFlags)
        let cursor = (currentTool == .pen) ? (penCursor ?? NSCursor.arrow) : (spotlightCursor ?? NSCursor.crosshair)
        cursor.set()
    }
    
    // MARK: - Shift Key & Modifier Tracking ("hold shift for spotlight, otherwise it's a pen all the time")
    
    public func startMonitoringModifiers() {
        stopMonitoringModifiers()
        
        // Listen globally for modifier flags (when another app has focus)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            DispatchQueue.main.async {
                self?.checkShiftModifier(event.modifierFlags)
            }
        }
        
        // Listen locally for modifier flags (when SpotPen has focus)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.checkShiftModifier(event.modifierFlags)
            return event
        }
        
        // 60Hz hardware poll timer to guarantee 0-latency detection regardless of key window focus
        let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.checkShiftModifier()
        }
        RunLoop.main.add(timer, forMode: .common)
        modifierCheckTimer = timer
        
        updateSpotlightPointToCurrentMouse()
        checkShiftModifier()
    }
    
    public func stopMonitoringModifiers() {
        if let global = globalEventMonitor {
            NSEvent.removeMonitor(global)
            globalEventMonitor = nil
        }
        if let local = localEventMonitor {
            NSEvent.removeMonitor(local)
            localEventMonitor = nil
        }
        modifierCheckTimer?.invalidate()
        modifierCheckTimer = nil
    }
    
    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        checkShiftModifier(event.modifierFlags)
    }
    
    public func isShiftDownNow(explicitFlags: NSEvent.ModifierFlags? = nil) -> Bool {
        if let flags = explicitFlags, flags.contains(.shift) {
            return true
        }
        if NSEvent.modifierFlags.contains(.shift) {
            return true
        }
        if CGEventSource.flagsState(.hidSystemState).contains(.maskShift) {
            return true
        }
        if CGEventSource.flagsState(.combinedSessionState).contains(.maskShift) {
            return true
        }
        if CGEventSource.keyState(.hidSystemState, key: 56) || CGEventSource.keyState(.hidSystemState, key: 60) {
            return true
        }
        if CGEventSource.keyState(.combinedSessionState, key: 56) || CGEventSource.keyState(.combinedSessionState, key: 60) {
            return true
        }
        return false
    }
    
    public func checkShiftModifier(_ explicitFlags: NSEvent.ModifierFlags? = nil) {
        let isShiftDown = isShiftDownNow(explicitFlags: explicitFlags)
        let targetTool: AnnotationTool = isShiftDown ? .spotlight : .pen
        
        if targetTool != currentTool {
            if currentTool == .pen && !currentStrokePoints.isEmpty {
                commitCurrentStroke()
            }
            currentTool = targetTool
            updateSpotlightPointToCurrentMouse()
            updateCursor()
            needsDisplay = true
        } else if currentTool == .spotlight {
            updateSpotlightPointToCurrentMouse()
        }
    }
    
    private func updateSpotlightPointToCurrentMouse() {
        guard let win = window else { return }
        let screenMouse = NSEvent.mouseLocation
        let winLoc = win.convertPoint(fromScreen: screenMouse)
        let viewPoint = convert(winLoc, from: nil)
        if viewPoint != spotlightPoint {
            spotlightPoint = viewPoint
            if currentTool == .spotlight {
                needsDisplay = true
            }
        }
    }
    
    // MARK: - Drawing Engine
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        // 1. Clear entire bounds to guarantee transparent background and erase previous spotlight frames
        ctx.clear(bounds)
        
        // 2. Draw Spotlight (entire screen darkened, with about 100px circle gradiented to transparency)
        if currentTool == .spotlight {
            drawSpotlight(in: ctx)
        }
        
        // 3. Draw Committed Strokes (drawn on top of the spotlight scrim)
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        
        // Slight shadow under pen strokes for natural elevation and depth
        ctx.setShadow(
            offset: Stroke.shadowOffset,
            blur: Stroke.shadowBlur,
            color: Stroke.shadowColor
        )
        
        for stroke in strokes {
            guard !stroke.points.isEmpty else { continue }
            ctx.setStrokeColor(stroke.color.cgColor)
            ctx.setLineWidth(stroke.lineWidth)
            
            let path = DrawingGeometry.buildSmoothPath(from: stroke.points)
            ctx.addPath(path)
            ctx.strokePath()
        }
        
        // 4. Draw Active In-Progress Stroke (with the same shadow)
        if currentTool == .pen && !currentStrokePoints.isEmpty {
            ctx.setStrokeColor(penColor.cgColor)
            ctx.setLineWidth(penWidth)
            
            let activePath = DrawingGeometry.buildSmoothPath(from: currentStrokePoints)
            ctx.addPath(activePath)
            ctx.strokePath()
        }
        
        ctx.restoreGState()
    }
    
    private func drawSpotlight(in ctx: CGContext) {
        ctx.saveGState()
        
        // 1. Overlay entire screen with darker scrim color
        ctx.setBlendMode(.normal)
        ctx.setFillColor(CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.72))
        ctx.fill(bounds)
        
        // 2. Punch about 100px circular aperture gradiented to transparency at the cursor
        if spotlightPunchGradient == nil {
            spotlightPunchGradient = DrawingGeometry.createSpotlightPunchGradient()
        }
        
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
        let point = convert(event.locationInWindow, from: nil)
        
        if currentTool == .spotlight {
            spotlightPoint = point
            needsDisplay = true
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        checkShiftModifier(event.modifierFlags)
        let point = convert(event.locationInWindow, from: nil)
        
        switch currentTool {
        case .pen:
            currentStrokePoints = [point]
            needsDisplay = true
            
        case .spotlight:
            spotlightPoint = point
            needsDisplay = true
        }
    }
    
    public override func mouseDragged(with event: NSEvent) {
        checkShiftModifier(event.modifierFlags)
        let point = convert(event.locationInWindow, from: nil)
        
        switch currentTool {
        case .pen:
            currentStrokePoints.append(point)
            needsDisplay = true
            
        case .spotlight:
            spotlightPoint = point
            needsDisplay = true
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        switch currentTool {
        case .pen:
            commitCurrentStroke()
            
        case .spotlight:
            break
        }
    }
    
    private func commitCurrentStroke() {
        guard !currentStrokePoints.isEmpty else { return }
        undoStack.append(strokes)
        let completedStroke = Stroke(
            points: currentStrokePoints,
            color: penColor,
            lineWidth: penWidth
        )
        strokes.append(completedStroke)
        currentStrokePoints = []
        needsDisplay = true
    }
    
    // MARK: - Independent Size Adjustment
    
    public override func scrollWheel(with event: NSEvent) {
        let isSpotlight = (currentTool == .spotlight) || isShiftDownNow(explicitFlags: event.modifierFlags)
        let rawDelta = (event.deltaY != 0) ? event.deltaY : event.scrollingDeltaY
        // Invert delta so scroll up enlarges size, scroll down shrinks size
        let delta = -rawDelta
        
        if isSpotlight {
            // Strictly independent: only changes spotlight size
            spotlightRadius = DrawingGeometry.clampRadius(spotlightRadius + delta * 2.5, min: 40.0, max: 400.0)
            updateCursor()
            needsDisplay = true
        } else {
            // Strictly independent: only changes pen size
            penWidth = min(max(penWidth + delta * 0.4, 1.0), 40.0)
            updateCursor()
            needsDisplay = true
        }
    }
    
    // MARK: - Canvas Actions
    
    public func clearAll() {
        guard !strokes.isEmpty || !currentStrokePoints.isEmpty else { return }
        undoStack.append(strokes)
        strokes.removeAll()
        currentStrokePoints.removeAll()
        needsDisplay = true
    }
    
    public func undoLastStroke() {
        guard let previousState = undoStack.popLast() else {
            if !strokes.isEmpty {
                strokes.removeLast()
                needsDisplay = true
            }
            return
        }
        strokes = previousState
        currentStrokePoints.removeAll()
        needsDisplay = true
    }
    
    // MARK: - Keyboard Event Handling
    
    public override func keyDown(with event: NSEvent) {
        // Esc (53): Close overlay
        if event.keyCode == 53 {
            delegate?.canvasDidRequestClose()
            return
        }
        
        // Key to clear screen: 'C' / 'c' (keyCode 8) or Backspace/Delete (keyCode 51 / 117)
        if event.keyCode == 8 || event.keyCode == 51 || event.keyCode == 117 {
            clearAll()
            return
        }
        
        // Cmd+Z: Undo
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers,
           chars.lowercased() == "z" {
            undoLastStroke()
            return
        }
        
        // '[' / ']': Independent size adjust
        if let chars = event.charactersIgnoringModifiers {
            let isSpotlight = (currentTool == .spotlight) || isShiftDownNow(explicitFlags: event.modifierFlags)
            
            if chars == "[" {
                if isSpotlight {
                    // Strictly independent: only changes spotlight size
                    spotlightRadius = DrawingGeometry.clampRadius(spotlightRadius - 15.0, min: 40.0, max: 400.0)
                } else {
                    // Strictly independent: only changes pen size
                    penWidth = max(penWidth - 1.5, 1.0)
                }
                updateCursor()
                needsDisplay = true
                return
            } else if chars == "]" {
                if isSpotlight {
                    // Strictly independent: only changes spotlight size
                    spotlightRadius = DrawingGeometry.clampRadius(spotlightRadius + 15.0, min: 40.0, max: 400.0)
                } else {
                    // Strictly independent: only changes pen size
                    penWidth = min(penWidth + 1.5, 40.0)
                }
                updateCursor()
                needsDisplay = true
                return
            }
        }
        
        super.keyDown(with: event)
    }
}
