import Foundation
import AppKit
import Carbon

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

/// Throwing assertion: a failure is reported by the runner instead of trapping the whole suite.
func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #fileID, line: UInt = #line) throws {
    if !condition() {
        throw TestFailure(description: "\(message) (\(file):\(line))")
    }
}

/// Isolated preferences so tests never touch the real app's settings or leave files behind.
enum TestDefaults {
    static let suiteName = "SpotPenTests"

    static func make() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    static func cleanUp() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}

private func mouse(_ type: NSEvent.EventType, _ point: NSPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    return NSEvent.mouseEvent(
        with: type,
        location: point,
        modifierFlags: flags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1.0
    )!
}

private func key(_ keyCode: Int, _ chars: String, flags: NSEvent.ModifierFlags) -> NSEvent {
    return NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: flags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: chars,
        charactersIgnoringModifiers: chars,
        isARepeat: false,
        keyCode: UInt16(keyCode)
    )!
}

private func flagsChanged(_ flags: NSEvent.ModifierFlags) -> NSEvent {
    return NSEvent.keyEvent(
        with: .flagsChanged,
        location: .zero,
        modifierFlags: flags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: 56 // left shift
    )!
}

private func drawStroke(on canvas: AnnotationCanvasView, from start: NSPoint, to end: NSPoint) {
    canvas.mouseDown(with: mouse(.leftMouseDown, start))
    canvas.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)))
    canvas.mouseDragged(with: mouse(.leftMouseDragged, end))
    canvas.mouseUp(with: mouse(.leftMouseUp, end))
}

/// Renders the whole canvas into a 1x bitmap and returns it.
private func render(_ canvas: AnnotationCanvasView) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.bounds.width),
        pixelsHigh: Int(canvas.bounds.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    canvas.draw(canvas.bounds)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Alpha at a view point (view origin is bottom-left, bitmap rows are top-down).
private func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
    return rep.colorAt(x: x, y: rep.pixelsHigh - 1 - y)?.alphaComponent ?? 0
}

private func hotKey(keyCode: Int, modifiers: Int, display: String) -> SavedHotKey {
    return SavedHotKey(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers), displayString: display, keyChar: "", modifierMaskRaw: 0)
}

public enum AppTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        defer { TestDefaults.cleanUp() }

        testRunner("AppConfig returns valid non-empty application name") {
            try expect(!AppConfig.appName.isEmpty, "App name should not be empty")
        }

        testRunner("AppConfig returns valid bundle identifier") {
            try expect(!AppConfig.bundleIdentifier.isEmpty, "Bundle identifier should not be empty")
            try expect(AppConfig.bundleIdentifier.contains("."), "Bundle identifier should be reverse-DNS style")
        }

        testRunner("AppConfig provides version and build number") {
            try expect(!AppConfig.version.isEmpty, "Version should not be empty")
            try expect(!AppConfig.buildNumber.isEmpty, "Build number should not be empty")
        }

        testRunner("StatusBarController builds the menu without an icon-mode chooser") {
            let controller = StatusBarController(hotKey: .defaultHotKey)
            let titles = controller.currentMenu.items.map(\.title)
            try expect(titles.contains { $0.contains("Quit") }, "Menu should contain quit item")
            try expect(titles.contains { $0.contains("Activate") }, "Menu should contain activate item")
            try expect(titles.contains { $0 == "Shortcut [⌃D]" }, "Menu should show the active shortcut")
            let shortcutItem = controller.currentMenu.items.first { $0.title.hasPrefix("Shortcut") }
            try expect(shortcutItem?.submenu == nil && shortcutItem?.action != nil, "Shortcut item records directly, no submenu")
            try expect(!titles.contains { $0.contains("Clear") || $0.contains("Undo") }, "No clear/undo: Esc wipes everything")
            try expect(!titles.contains { $0.contains("Status Bar Icon") }, "Icon appearance is automatic; no chooser")
            NSStatusBar.system.removeStatusItem(controller.currentStatusItem)
        }

        testRunner("Status bar icon is an 18pt template image (adapts to light and dark menu bars)") {
            let icon = StatusBarController.loadIcon()
            try expect(icon.size == NSSize(width: 18, height: 18), "Icon should be 18x18")
            try expect(icon.isTemplate, "Icon must be a template image so macOS tints it")
        }

        testRunner("StatusBarController marks an unregistered shortcut as unavailable") {
            let controller = StatusBarController(hotKey: .defaultHotKey, isHotKeyActive: false)
            let titles = controller.currentMenu.items.map(\.title)
            try expect(titles.contains { $0.contains("unavailable") }, "Inactive shortcut must be labelled unavailable")
            NSStatusBar.system.removeStatusItem(controller.currentStatusItem)
        }

        testRunner("SavedHotKey parses ⌘⇧P and F-keys") {
            try expect(SavedHotKey.defaultHotKey.displayString == "⌃D", "Default shortcut must be ⌃D")
            let parsed = SavedHotKey.from(event: key(kVK_ANSI_P, "P", flags: [.command, .shift]))
            try expect(parsed?.displayString == "⇧⌘P", "Should parse ⌘⇧P, got \(String(describing: parsed?.displayString))")
            try expect(parsed?.keyChar == "p", "Menu key equivalent must be the unshifted character")
            try expect(SavedHotKey.from(event: key(kVK_F5, "", flags: [])) != nil, "Bare F-keys are allowed")
            try expect(SavedHotKey.from(event: key(kVK_F12, "", flags: [])) != nil, "F10-F12 are F-keys too")
        }

        testRunner("SavedHotKey rejects shortcuts that would hijack typing") {
            let rejected: [(NSEvent.ModifierFlags, Int, String)] = [
                ([.shift], kVK_ANSI_A, "⇧A"),
                ([.option], kVK_ANSI_A, "⌥A"),
                ([.option], kVK_Space, "⌥Space"),
                ([.option, .shift], kVK_ANSI_E, "⌥⇧E"),
                ([], kVK_ANSI_A, "A")
            ]
            for (flags, code, name) in rejected {
                let result = SavedHotKey.parse(event: key(code, "a", flags: flags))
                try expect(result.failureValue == .needsCommandOrControl, "\(name) must be rejected")
            }
            try expect(SavedHotKey.parse(event: key(kVK_LeftArrow, "", flags: [.command])).failureValue == .unsupportedKey, "Unknown keys are rejected")
            try expect(SavedHotKey.presets.allSatisfy(\.isAllowedAsGlobalShortcut), "Every preset must be allowed")
        }

        testRunner("SavedHotKey.load ignores saved shortcuts that are no longer allowed") {
            let defaults = TestDefaults.make()
            hotKey(keyCode: kVK_Space, modifiers: optionKey, display: "⌥Space").save(to: defaults)
            try expect(SavedHotKey.load(from: defaults) == .defaultHotKey, "Option-only shortcut falls back to the default")
            let allowed = hotKey(keyCode: kVK_ANSI_K, modifiers: controlKey | optionKey | cmdKey, display: "⌃⌥⌘K")
            allowed.save(to: defaults)
            try expect(SavedHotKey.load(from: defaults) == allowed, "Allowed shortcut round-trips")
        }

        testRunner("HotKeyManager keeps the previous shortcut when registration fails") {
            // Unusual combinations so the test never collides with the user's real shortcuts.
            let first = hotKey(keyCode: kVK_F11, modifiers: controlKey | optionKey | shiftKey | cmdKey, display: "⌃⌥⇧⌘F11")
            let second = hotKey(keyCode: kVK_F12, modifiers: controlKey | optionKey | shiftKey | cmdKey, display: "⌃⌥⇧⌘F12")

            let defaultsA = TestDefaults.make()
            first.save(to: defaultsA)
            let ownerA = HotKeyManager(defaults: defaultsA) {}
            try expect(ownerA.isRegistered && ownerA.currentHotKey == first, "First manager registers its saved shortcut")

            let defaultsB = UserDefaults(suiteName: TestDefaults.suiteName + ".B")!
            defer { defaultsB.removePersistentDomain(forName: TestDefaults.suiteName + ".B") }
            second.save(to: defaultsB)
            let managerB = HotKeyManager(defaults: defaultsB) {}
            try expect(managerB.isRegistered && managerB.currentHotKey == second, "Second manager registers its saved shortcut")

            // `first` is already taken, so this must fail without disturbing B's working shortcut.
            let result = managerB.registerHotKey(first)
            try expect(result.failureValue != nil, "Registering a taken combination must fail")
            try expect(managerB.isRegistered, "Previous shortcut must stay registered")
            try expect(managerB.currentHotKey == second, "Current shortcut must be unchanged")
            try expect(SavedHotKey.load(from: defaultsB) == second, "A failed shortcut must not be saved")

            let shiftOnly = hotKey(keyCode: kVK_ANSI_A, modifiers: shiftKey, display: "⇧A")
            try expect(managerB.registerHotKey(shiftOnly).failureValue == .needsCommandOrControl, "Manager refuses unsafe shortcuts")
        }

        testRunner("Models enforce single pen color, shadow, and valid strokes") {
            let stroke1 = Stroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20)])
            try expect(stroke1.color == Stroke.defaultColor, "Stroke must use the single default pen color")
            try expect(abs(Stroke.defaultColor.alphaComponent - 0.90) < 0.01, "Pen color must be 10% transparent (0.90 alpha)")
            try expect(stroke1.lineWidth == 4.0, "Stroke default line width should be 4.0")
            try expect(Stroke.shadowBlur > 0.0 && Stroke.shadowOffset.height != 0.0 && Stroke.shadowColor.alpha > 0.0, "Pen must have a shadow")
        }

        testRunner("DrawingGeometry calculates midpoint, distance, and ink bounds") {
            let mid = DrawingGeometry.midPoint(CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40))
            try expect(abs(mid.x - 20.0) < 0.001 && abs(mid.y - 30.0) < 0.001, "Midpoint calculation failed")
            try expect(abs(DrawingGeometry.distance(.zero, CGPoint(x: 3, y: 4)) - 5.0) < 0.001, "Distance calculation failed")

            try expect(DrawingGeometry.boundingRect(of: [CGPoint]()).isNull, "Empty points have no bounds")
            let ink = DrawingGeometry.inkRect(of: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 30)], lineWidth: 10)
            try expect(ink.minX < 10 - 5 && ink.maxX > 50 + 5 && ink.minY < 10 - 5, "Ink rect must cover caps and shadow")
        }

        testRunner("DrawingGeometry builds smooth paths for points") {
            try expect(DrawingGeometry.buildSmoothPath(from: []).isEmpty, "Empty points should yield empty path")
            try expect(!DrawingGeometry.buildSmoothPath(from: [CGPoint(x: 5, y: 5)]).isEmpty, "Single point should yield non-empty path")
            let multi = DrawingGeometry.buildSmoothPath(from: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 50), CGPoint(x: 40, y: 10), CGPoint(x: 80, y: 90)])
            try expect(!multi.isEmpty, "Multi points should yield non-empty spline")
        }

        testRunner("DrawingGeometry creates spotlight gradient and clamps radius") {
            try expect(DrawingGeometry.createSpotlightPunchGradient() != nil, "Spotlight gradient must be valid and non-nil")
            try expect(DrawingGeometry.clampRadius(20, min: 40, max: 400) == 40, "Clamp minimum failed")
            try expect(DrawingGeometry.clampRadius(800, min: 40, max: 400) == 400, "Clamp maximum failed")
            try expect(DrawingGeometry.clampRadius(100, min: 40, max: 400) == 100, "Clamp mid failed")
        }

        testRunner("CursorFactory creates pen cursor that grows with size, and spotlight cursor") {
            let penCursor = CursorFactory.makePenCursor(penWidth: 4.0)
            try expect(penCursor.hotSpot.x == penCursor.image.size.width / 2.0, "Pen cursor hotSpot X must be centered")
            try expect(penCursor.hotSpot.y == penCursor.image.size.height / 2.0, "Pen cursor hotSpot Y must be centered")
            try expect(CursorFactory.makePenCursor(penWidth: 20.0).image.size.width > penCursor.image.size.width, "Pen cursor must grow with size")

            try expect(penCursor.image.size.width <= 10, "Pen cursor is a small dot, not a reticle")

            let spotlightCursor = CursorFactory.makeSpotlightCursor()
            try expect(spotlightCursor.image.size == NSSize(width: 3, height: 3) && spotlightCursor.hotSpot.x == 1.5, "Spotlight cursor is a centred 3x3 cross")
            guard let rep = spotlightCursor.image.representations.compactMap({ $0 as? NSBitmapImageRep }).first(where: { $0.pixelsWide == 3 }) else {
                throw TestFailure(description: "Spotlight cursor needs a 3x3 bitmap")
            }
            let a = { (x: Int, y: Int) in rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
            try expect(abs(a(1, 1) - CursorFactory.spotlightCrossAlpha) < 0.01 && a(1, 0) > 0 && a(0, 1) > 0, "Cross pixels are slightly transparent")
            try expect(a(0, 0) == 0 && a(2, 2) == 0, "Cross corners are empty")
        }

        testRunner("AnnotationCanvasView reuses cursors until the pen width really changes") {
            let canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
            let first = canvas.activeCursor
            try expect(canvas.activeCursor === first, "Unchanged width must reuse the cursor")
            canvas.penWidth += 0.1
            try expect(canvas.activeCursor === first, "Sub-half-point change must reuse the cursor")
            canvas.penWidth += 2.0
            try expect(canvas.activeCursor !== first, "Real width change must rebuild the cursor")
            canvas.penWidth = 500
            try expect(canvas.penWidth == AnnotationCanvasView.penWidthRange.upperBound, "Pen width is clamped")
        }

        testRunner("AnnotationCanvasView draws and clears strokes without keeping history") {
            let canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            try expect(canvas.currentTool == .pen, "Canvas must default to .pen tool")
            try expect(canvas.penColor == Stroke.defaultColor, "Canvas must use single pen color")
            try expect(canvas.strokes.isEmpty, "Initial strokes must be empty")

            drawStroke(on: canvas, from: NSPoint(x: 100, y: 100), to: NSPoint(x: 150, y: 150))
            drawStroke(on: canvas, from: NSPoint(x: 200, y: 100), to: NSPoint(x: 250, y: 150))
            try expect(canvas.strokes.count == 2, "Should have 2 committed strokes")
            try expect(canvas.strokes[0].color == Stroke.defaultColor, "Committed stroke must have single pen color")

            canvas.keyDown(with: key(kVK_ANSI_Z, "z", flags: [.command]))
            try expect(canvas.strokes.count == 2, "Cmd+Z does nothing: there is no undo")
            canvas.keyDown(with: key(kVK_ANSI_C, "c", flags: [.command]))
            try expect(canvas.strokes.count == 2, "Cmd+C does not clear")
            canvas.keyDown(with: key(kVK_ANSI_C, "c", flags: []))
            try expect(canvas.strokes.isEmpty, "C clears the screen")
            drawStroke(on: canvas, from: NSPoint(x: 100, y: 100), to: NSPoint(x: 150, y: 150))
            try expect(canvas.strokes.count == 1, "Drawing continues after C")
        }

        testRunner("Esc clears the canvas and asks to close") {
            final class Spy: AnnotationCanvasDelegate {
                var closed = 0
                func canvasDidRequestClose() { closed += 1 }
            }
            let canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            let spy = Spy()
            canvas.delegate = spy
            drawStroke(on: canvas, from: NSPoint(x: 10, y: 10), to: NSPoint(x: 60, y: 60))
            canvas.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 100, y: 100)))
            canvas.keyDown(with: key(kVK_Escape, "\u{1b}", flags: []))
            try expect(canvas.strokes.isEmpty, "Esc wipes committed strokes")
            try expect(spy.closed == 1, "Esc closes the overlay")
            canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 100, y: 100)))
            try expect(canvas.strokes.isEmpty, "Esc also drops the stroke in progress")
        }

        testRunner("AnnotationCanvasView renders committed and in-progress strokes identically") {
            let canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            canvas.backingScaleOverride = 1.0 // match the 1x test bitmap (2x was verified on a real Retina window)
            drawStroke(on: canvas, from: NSPoint(x: 40, y: 50), to: NSPoint(x: 260, y: 50))
            canvas.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 40, y: 140)))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 260, y: 140)))

            let rep = render(canvas)
            try expect(alpha(rep, 150, 50) > 0.8, "Committed stroke must be drawn from the cache")
            try expect(alpha(rep, 150, 140) > 0.8, "In-progress stroke must be drawn")
            for dy in -12...12 {
                try expect(abs(alpha(rep, 150, 50 + dy) - alpha(rep, 150, 140 + dy)) < 0.02, "Ink and shadow profile must match at offset \(dy)")
            }
            try expect(alpha(rep, 150, 95) == 0, "Background stays transparent")
            canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 260, y: 140)))
        }

        testRunner("AnnotationCanvasView renders the spotlight scrim with a clear aperture") {
            let canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            canvas.flagsChanged(with: flagsChanged([.shift]))
            canvas.spotlightPoint = CGPoint(x: 200, y: 150)
            let rep = render(canvas)
            try expect(alpha(rep, 200, 150) < 0.02, "Aperture centre is transparent")
            try expect(abs(alpha(rep, 10, 10) - 0.72) < 0.02, "Outside the aperture the scrim is 72% dark")
        }

        testRunner("AnnotationCanvasView switches to spotlight while shift is held and back to pen") {
            let canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            canvas.flagsChanged(with: flagsChanged([.shift]))
            try expect(canvas.currentTool == .spotlight, "Canvas should switch to .spotlight when Shift is held")
            canvas.flagsChanged(with: flagsChanged([]))
            try expect(canvas.currentTool == .pen, "Canvas should return to .pen when Shift is released")

            // Regression: switching tools triggers a cursorUpdate whose flags are empty; it must not undo the switch.
            canvas.flagsChanged(with: flagsChanged([.shift]))
            let cursorUpdate = NSEvent.enterExitEvent(
                with: .cursorUpdate, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
            )!
            canvas.cursorUpdate(with: cursorUpdate)
            try expect(canvas.currentTool == .spotlight, "cursorUpdate must not cancel the spotlight while Shift is held")
            canvas.flagsChanged(with: flagsChanged([]))
            
            canvas.mouseMoved(with: mouse(.mouseMoved, NSPoint(x: 10, y: 10), flags: [.shift]))
            try expect(canvas.currentTool == .spotlight, "Mouse events carry Shift state too")
            canvas.mouseMoved(with: mouse(.mouseMoved, NSPoint(x: 10, y: 10)))
            try expect(canvas.currentTool == .pen, "Releasing Shift is seen on the next mouse event")
        }

        testRunner("Scroll wheel, trackpad and [ ] resize pen and spotlight together") {
            let canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            let radius = canvas.spotlightRadius, width = canvas.penWidth
            canvas.adjustSize(byScrollPoints: 40)
            try expect(canvas.spotlightRadius > radius && canvas.penWidth > width, "Growing affects both tools")
            canvas.adjustSize(byScrollPoints: -40)
            try expect(abs(canvas.spotlightRadius - radius) < 0.001 && abs(canvas.penWidth - width) < 0.001, "Shrinking affects both tools")

            canvas.flagsChanged(with: flagsChanged([.shift]))
            canvas.keyDown(with: key(kVK_ANSI_RightBracket, "}", flags: [.shift]))
            try expect(canvas.spotlightRadius > radius && canvas.penWidth > width, "Shift+] grows both")
            canvas.flagsChanged(with: flagsChanged([]))
            canvas.keyDown(with: key(kVK_ANSI_LeftBracket, "[", flags: []))
            try expect(abs(canvas.spotlightRadius - radius) < 0.001 && abs(canvas.penWidth - width) < 0.001, "[ shrinks both")

            for (dy, dx) in [(CGFloat(3), CGFloat(0)), (0, 3)] { // vertical wheel, and Shift+wheel (sent as horizontal)
                let before = canvas.spotlightRadius
                let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)!
                canvas.scrollWheel(with: NSEvent(cgEvent: cg)!)
                try expect(canvas.spotlightRadius != before, "Scroll (dy \(dy), dx \(dx)) must resize")
            }
        }
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
