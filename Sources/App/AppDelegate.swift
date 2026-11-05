import Cocoa

public final class AppDelegate: NSObject, NSApplicationDelegate, OverlayWindowDelegate, StatusBarControllerDelegate {
    private var overlayController: OverlayWindowController!
    private var hotKeyManager: HotKeyManager!
    private var statusBarController: StatusBarController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        overlayController = OverlayWindowController()
        overlayController.delegate = self
        
        statusBarController = StatusBarController()
        statusBarController.delegate = self
        
        hotKeyManager = HotKeyManager { [weak self] in
            self?.handleGlobalHotKey()
        }
        
        // Keep status bar synchronized with active hotkey
        statusBarController.updateHotKey(hotKeyManager.currentHotKey)
        
        // Setup custom shortcut recorder callback
        ShortcutRecorderWindow.shared.onHotKeyRecorded = { [weak self] newHotKey in
            guard let self = self else { return }
            self.hotKeyManager.registerHotKey(newHotKey)
            self.statusBarController.updateHotKey(newHotKey)
        }
        
        NSLog("%@ started successfully. Press %@ or click the menu bar icon to annotate.", AppConfig.appName, hotKeyManager.currentHotKey.displayString)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    private func handleGlobalHotKey() {
        overlayController.toggle()
        statusBarController.updateOverlayVisibility(isVisible: overlayController.isVisible)
    }
    
    // MARK: - OverlayWindowDelegate
    
    public func overlayWindowDidDismiss() {
        statusBarController.updateOverlayVisibility(isVisible: false)
    }
    
    // MARK: - StatusBarControllerDelegate
    
    public func statusBarDidRequestToggle() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.overlayController.toggle()
            self.statusBarController.updateOverlayVisibility(isVisible: self.overlayController.isVisible)
        }
    }
    
    public func statusBarDidSelectHotKey(_ hotKey: SavedHotKey) {
        hotKeyManager.registerHotKey(hotKey)
    }
    
    public func statusBarDidRequestRecordShortcut() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            ShortcutRecorderWindow.shared.show(currentHotKey: self.hotKeyManager.currentHotKey)
        }
    }
    
    public func statusBarDidRequestClear() {
        DispatchQueue.main.async { [weak self] in
            self?.overlayController.canvasView.clearAll()
        }
    }
    
    public func statusBarDidRequestUndo() {
        DispatchQueue.main.async { [weak self] in
            self?.overlayController.canvasView.undoLastStroke()
        }
    }
    
    public func statusBarDidRequestQuit() {
        NSApp.terminate(nil)
    }
}
