import AppKit

public final class CustomBorderlessWindow: NSWindow {
    public override var canBecomeKey: Bool { return true }
    public override var canBecomeMain: Bool { return true }
    
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            (contentView as? AnnotationCanvasView)?.checkShiftModifier()
        }
        super.sendEvent(event)
    }
}

public protocol OverlayWindowDelegate: AnyObject {
    func overlayWindowDidDismiss()
}

public final class OverlayWindowController: NSObject, AnnotationCanvasDelegate {
    public weak var delegate: OverlayWindowDelegate?
    
    public private(set) var window: CustomBorderlessWindow!
    public private(set) var canvasView: AnnotationCanvasView!
    
    public var isVisible: Bool {
        return window?.isVisible ?? false
    }
    
    public override init() {
        super.init()
        buildWindow()
    }
    
    deinit {
        canvasView?.stopMonitoringModifiers()
    }
    
    private func buildWindow() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        
        window = CustomBorderlessWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.acceptsMouseMovedEvents = true
        
        canvasView = AnnotationCanvasView(frame: screenFrame)
        canvasView.delegate = self
        canvasView.autoresizingMask = [.width, .height]
        window.contentView = canvasView
    }
    
    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    public func show() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        
        if let currentScreen = targetScreen {
            window.setFrame(currentScreen.frame, display: true)
            canvasView.frame = window.contentView?.bounds ?? currentScreen.frame
            
            let windowMouseLoc = window.convertPoint(fromScreen: mouseLocation)
            canvasView.spotlightPoint = canvasView.convert(windowMouseLoc, from: nil)
        }
        
        window.alphaValue = 0.0
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(canvasView)
        
        canvasView.startMonitoringModifiers()
        canvasView.updateCursor()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1.0
        }
    }
    
    public func hide() {
        canvasView.stopMonitoringModifiers()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.window.orderOut(nil)
            self.delegate?.overlayWindowDidDismiss()
        })
    }
    
    // MARK: - AnnotationCanvasDelegate
    
    public func canvasDidRequestClose() {
        hide()
    }
}
