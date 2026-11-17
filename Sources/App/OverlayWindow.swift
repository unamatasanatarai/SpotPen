import AppKit

public final class CustomBorderlessWindow: NSWindow {
    public override var canBecomeKey: Bool { return true }
    public override var canBecomeMain: Bool { return true }
}

public final class OverlayWindowController: NSObject, AnnotationCanvasDelegate {
    public private(set) var window: CustomBorderlessWindow!
    public private(set) var canvasView: AnnotationCanvasView!

    /// Display the overlay is currently shown on.
    private var displayID: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?
    private var isHiding = false

    /// True while the overlay is shown and not fading out.
    public var isVisible: Bool {
        return (window?.isVisible ?? false) && !isHiding
    }

    public override init() {
        super.init()
        buildWindow()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenParametersDidChange()
        }
    }

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.acceptsMouseMovedEvents = true

        canvasView = AnnotationCanvasView(frame: screenFrame)
        canvasView.delegate = self
        canvasView.autoresizingMask = [.width, .height]
        window.contentView = canvasView
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Activation shortcut: shows the overlay, or wipes and hides it when it is already up (like Esc).
    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Shows the overlay on the screen under the mouse, always with an empty canvas.
    /// If it is already up, only brings it back into focus and keeps the drawing.
    public func show() {
        if isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(canvasView)
            return
        }
        // Showing again during the fade-out cancels the pending orderOut.
        isHiding = false
        // A drag still in progress when the previous session was dismissed can commit a stroke
        // after hide() wiped the canvas; nothing from an earlier session may survive.
        canvasView.clearAll()

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main

        if let currentScreen = targetScreen {
            displayID = Self.displayID(of: currentScreen)
            window.setFrame(currentScreen.frame, display: false)
        }

        window.alphaValue = 0.0
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(canvasView)

        canvasView.prepareForPresentation()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1.0
        }
    }

    /// Wipes the annotations and fades the overlay out. Nothing is kept for next time.
    public func hide() {
        guard window.isVisible, !isHiding else { return }
        isHiding = true
        canvasView.clearAll()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self, self.isHiding else { return }
            self.isHiding = false
            self.window.orderOut(nil)
            self.canvasView.releaseRenderCache()
        })
    }

    /// Keeps the overlay fitted to its display when resolution or arrangement changes,
    /// and hides it if that display was disconnected.
    private func screenParametersDidChange() {
        guard window.isVisible, !isHiding else { return }
        if let screen = NSScreen.screens.first(where: { Self.displayID(of: $0) == displayID }) {
            window.setFrame(screen.frame, display: true)
        } else {
            hide()
        }
    }

    // MARK: - AnnotationCanvasDelegate

    public func canvasDidRequestClose() {
        hide()
    }
}
