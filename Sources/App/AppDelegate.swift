import Cocoa

public final class AppDelegate: NSObject, NSApplicationDelegate, OverlayWindowDelegate, StatusBarControllerDelegate {
    private var overlayController: OverlayWindowController!
    private var hotKeyManager: HotKeyManager!
    private var statusBarController: StatusBarController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlayController = OverlayWindowController()
        overlayController.delegate = self

        hotKeyManager = HotKeyManager { [weak self] in
            self?.handleGlobalHotKey()
        }

        statusBarController = StatusBarController(
            hotKey: hotKeyManager.currentHotKey,
            isHotKeyActive: hotKeyManager.isRegistered
        )
        statusBarController.delegate = self

        // Custom shortcut recorder: the recorder shows the error itself when registration fails.
        ShortcutRecorderWindow.shared.onHotKeyRecorded = { [weak self] newHotKey in
            guard let self = self else { return .success(()) }
            return self.applyHotKey(newHotKey)
        }

        NSLog("%@ started successfully. Press %@ or click the menu bar icon to annotate.", AppConfig.appName, hotKeyManager.currentHotKey.displayString)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func handleGlobalHotKey() {
        overlayController.toggle()
    }

    /// Registers the shortcut and updates the menu only if the system accepted it.
    private func applyHotKey(_ hotKey: SavedHotKey) -> Result<Void, ShortcutError> {
        let result = hotKeyManager.registerHotKey(hotKey)
        statusBarController.updateHotKey(hotKeyManager.currentHotKey, isActive: hotKeyManager.isRegistered)
        return result
    }

    // MARK: - OverlayWindowDelegate

    public func overlayWindowDidDismiss() {}

    // MARK: - StatusBarControllerDelegate

    public func statusBarDidRequestActivate() {
        DispatchQueue.main.async { [weak self] in
            self?.overlayController.show()
        }
    }

    public func statusBarDidRequestRecordShortcut() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            ShortcutRecorderWindow.shared.show(currentHotKey: self.hotKeyManager.currentHotKey)
        }
    }

    public func statusBarDidRequestQuit() {
        NSApp.terminate(nil)
    }
}
