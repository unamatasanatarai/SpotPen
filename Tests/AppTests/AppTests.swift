import Foundation
import AppKit

public enum AppTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("AppConfig returns valid non-empty application name") {
            assert(!AppConfig.appName.isEmpty, "App name should not be empty")
        }

        testRunner("AppConfig returns valid bundle identifier") {
            assert(!AppConfig.bundleIdentifier.isEmpty, "Bundle identifier should not be empty")
            assert(AppConfig.bundleIdentifier.contains("."), "Bundle identifier should be reverse-DNS style")
        }

        testRunner("AppConfig provides version string") {
            assert(!AppConfig.version.isEmpty, "Version should not be empty")
        }

        testRunner("AppConfig provides build number") {
            assert(!AppConfig.buildNumber.isEmpty, "Build number should not be empty")
        }

        testRunner("StatusBarController initializes menu correctly and supports light/dark icon modes") {
            let controller = StatusBarController()
            assert(controller.currentMenu.items.count >= 5, "Menu should have items")
            assert(controller.currentMenu.items.contains { $0.title.contains("Quit") }, "Menu should contain quit item")
            assert(controller.currentMenu.items.contains { $0.title.contains("Toggle") }, "Menu should contain toggle item")
            assert(controller.currentMenu.items.contains { $0.title.contains("Shortcut") }, "Menu should contain shortcut item")
            assert(controller.currentMenu.items.contains { $0.title.contains("Clear") }, "Menu should contain clear item")
            assert(controller.currentMenu.items.contains { $0.title.contains("Status Bar Icon") }, "Menu should contain status bar icon item")
            
            // Test icon modes switching
            controller.setIconMode(.light)
            assert(controller.currentIconMode == .light, "Icon mode should switch to light")
            let lightIcon = StatusBarController.loadIcon(for: .light)
            assert(lightIcon.size.width == 18.0 && lightIcon.size.height == 18.0, "Light icon should be 18x18")
            
            controller.setIconMode(.dark)
            assert(controller.currentIconMode == .dark, "Icon mode should switch to dark")
            let darkIcon = StatusBarController.loadIcon(for: .dark)
            assert(darkIcon.size.width == 18.0 && darkIcon.size.height == 18.0, "Dark icon should be 18x18")
            
            controller.setIconMode(.auto)
            assert(controller.currentIconMode == .auto, "Icon mode should switch to auto")
            let autoIcon = StatusBarController.loadIcon(for: .auto)
            assert(autoIcon.size.width == 18.0 && autoIcon.size.height == 18.0, "Auto icon should be 18x18")
            assert(autoIcon.isTemplate == true, "Auto icon should be a template image")
        }

        testRunner("SavedHotKey parses events and persists correctly") {
            let defaultHK = SavedHotKey.defaultHotKey
            assert(defaultHK.displayString == "⌘⇧A", "Default shortcut must be ⌘⇧A")
            assert(!SavedHotKey.presets.isEmpty, "Presets should not be empty")
            
            // Simulate ⌘⇧P key event
            let eventP = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "p",
                charactersIgnoringModifiers: "p",
                isARepeat: false,
                keyCode: 35 // kVK_ANSI_P
            )!
            let parsed = SavedHotKey.from(event: eventP)
            assert(parsed != nil, "Should parse ⌘⇧P event")
            assert(parsed?.displayString == "⇧⌘P" || parsed?.displayString.contains("P") == true, "Display string must contain P")
        }

        testRunner("Models enforce single pen color, shadow, and valid strokes") {
            let stroke1 = Stroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20)])
            assert(stroke1.color == Stroke.defaultColor, "Stroke must use the single default pen color")
            assert(abs(Stroke.defaultColor.alphaComponent - 0.90) < 0.01, "Pen color must be 10% transparent (0.90 alpha)")
            assert(stroke1.lineWidth == 4.0, "Stroke default line width should be 4.0")
            assert(stroke1.points.count == 2, "Stroke points count should match")
            
            let stroke2 = Stroke(points: [CGPoint(x: 30, y: 30)])
            assert(stroke2.color == Stroke.defaultColor, "Stroke 2 must also use single default pen color")
            
            // Validate slight shadow under pen
            assert(Stroke.shadowBlur > 0.0, "Pen must have shadow blur")
            assert(Stroke.shadowOffset.height != 0.0, "Pen must have shadow vertical offset")
            assert(Stroke.shadowColor.alpha > 0.0, "Pen shadow must have opacity")
        }

        testRunner("DrawingGeometry calculates midpoint and distance accurately") {
            let p1 = CGPoint(x: 10, y: 20)
            let p2 = CGPoint(x: 30, y: 40)
            
            let mid = DrawingGeometry.midPoint(p1, p2)
            assert(abs(mid.x - 20.0) < 0.001, "Midpoint X calculation failed")
            assert(abs(mid.y - 30.0) < 0.001, "Midpoint Y calculation failed")
            
            let dist = DrawingGeometry.distance(CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4))
            assert(abs(dist - 5.0) < 0.001, "Distance calculation failed")
        }

        testRunner("DrawingGeometry builds smooth paths for points") {
            let emptyPath = DrawingGeometry.buildSmoothPath(from: [])
            assert(emptyPath.isEmpty, "Empty points should yield empty path")
            
            let single = DrawingGeometry.buildSmoothPath(from: [CGPoint(x: 5, y: 5)])
            assert(!single.isEmpty, "Single point should yield non-empty path")
            
            let multi = DrawingGeometry.buildSmoothPath(from: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 20, y: 50),
                CGPoint(x: 40, y: 10),
                CGPoint(x: 80, y: 90)
            ])
            assert(!multi.isEmpty, "Multi points should yield non-empty spline")
        }

        testRunner("DrawingGeometry creates gentle spotlight radial gradient") {
            let gradient = DrawingGeometry.createSpotlightPunchGradient()
            assert(gradient != nil, "Spotlight gradient must be valid and non-nil")
            
            assert(DrawingGeometry.clampRadius(20, min: 40, max: 400) == 40, "Clamp minimum failed")
            assert(DrawingGeometry.clampRadius(800, min: 40, max: 400) == 400, "Clamp maximum failed")
            assert(DrawingGeometry.clampRadius(100, min: 40, max: 400) == 100, "Clamp mid failed")
        }

        testRunner("CursorFactory creates pen cursor as circle with target and spotlight cursor") {
            let penCursor = CursorFactory.makePenCursor(penWidth: 4.0)
            assert(penCursor.hotSpot.x == penCursor.image.size.width / 2.0, "Pen cursor hotSpot X must be centered")
            assert(penCursor.hotSpot.y == penCursor.image.size.height / 2.0, "Pen cursor hotSpot Y must be centered")
            
            let largePenCursor = CursorFactory.makePenCursor(penWidth: 20.0)
            assert(largePenCursor.image.size.width > penCursor.image.size.width, "Pen cursor must grow with size")
            
            let spotlightCursor = CursorFactory.makeSpotlightCursor()
            assert(spotlightCursor.image.size.width == 32, "Spotlight cursor width should be 32")
            assert(spotlightCursor.hotSpot.x == 16.0, "Spotlight cursor hotSpot X must be center (16)")
        }

        testRunner("AnnotationCanvasView enforces single pen color, default pen tool, and undo/clear") {
            let canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            assert(canvas.currentTool == .pen, "Canvas must default to .pen tool")
            assert(canvas.penColor == Stroke.defaultColor, "Canvas must use single pen color")
            assert(canvas.strokes.isEmpty, "Initial strokes must be empty")
            
            // Mouse down / dragged / up simulation
            let downEvent = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 100, y: 100),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1.0
            )!
            canvas.mouseDown(with: downEvent)
            
            let dragEvent = NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: NSPoint(x: 150, y: 150),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 1.0
            )!
            canvas.mouseDragged(with: dragEvent)
            
            let upEvent = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: NSPoint(x: 150, y: 150),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 3,
                clickCount: 1,
                pressure: 0.0
            )!
            canvas.mouseUp(with: upEvent)
            
            assert(canvas.strokes.count == 1, "Should have 1 committed stroke")
            assert(canvas.strokes[0].color == Stroke.defaultColor, "Committed stroke must have single pen color")
            
            // Undo
            canvas.undoLastStroke()
            assert(canvas.strokes.isEmpty, "Undo should restore empty strokes")
            
            // Clear
            canvas.mouseDown(with: downEvent)
            canvas.mouseUp(with: upEvent)
            assert(canvas.strokes.count == 1, "Should have 1 stroke")
            canvas.clearAll()
            assert(canvas.strokes.isEmpty, "Clear all should empty strokes")
        }

        testRunner("AnnotationCanvasView switches to spotlight when shift is held and returns to pen") {
            let canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            assert(canvas.currentTool == .pen, "Canvas starts in pen mode")
            
            // Simulate Shift key press
            let shiftDownEvent = NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: [.shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 56 // left shift
            )!
            canvas.flagsChanged(with: shiftDownEvent)
            assert(canvas.currentTool == .spotlight, "Canvas should switch to .spotlight when Shift is held")
            
            // Simulate Shift key release
            let shiftUpEvent = NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 56
            )!
            canvas.flagsChanged(with: shiftUpEvent)
            assert(canvas.currentTool == .pen, "Canvas should return to .pen when Shift is released")
        }
    }
}
