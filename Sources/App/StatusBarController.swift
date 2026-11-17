import Cocoa

public protocol StatusBarControllerDelegate: AnyObject {
    func statusBarDidRequestActivate()
    func statusBarDidRequestQuit()
    func statusBarDidRequestRecordShortcut()
}

public final class StatusBarController: NSObject, NSMenuDelegate {
    public weak var delegate: StatusBarControllerDelegate?

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var activateItem: NSMenuItem!
    private var shortcutItem: NSMenuItem!

    public init(hotKey: SavedHotKey = .defaultHotKey, isHotKeyActive: Bool = true) {
        super.init()
        setupStatusItem()
        setupMenu()
        updateHotKey(hotKey, isActive: isHotKeyActive)
    }

    public var currentMenu: NSMenu {
        return menu
    }

    public var currentStatusItem: NSStatusItem {
        return statusItem
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.loadIcon()
            button.imagePosition = .imageOnly
        }
    }

    /// Menu bar icon as a template image: macOS tints it automatically for light and dark
    /// menu bars (and wallpaper-dependent menu bar appearance), so no manual choice is needed.
    public static func loadIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        for name in ["StatusBarIcon", "StatusBarIcon@2x"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let rep = NSImageRep(contentsOf: url) {
                rep.size = size
                image.addRepresentation(rep)
            }
        }

        let icon = image.representations.isEmpty ? renderFallbackIcon() : image
        icon.isTemplate = true
        return icon
    }

    /// Drawn icon used when the bundled PNGs are missing (e.g. when running tests outside the app bundle).
    private static func renderFallbackIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return img }

        ctx.setStrokeColor(NSColor.black.cgColor)

        // Outer circle
        ctx.addArc(center: CGPoint(x: 9, y: 9), radius: 6.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setLineWidth(1.5)
        ctx.strokePath()

        // Angled pen
        ctx.move(to: CGPoint(x: 4.5, y: 4.5))
        ctx.addLine(to: CGPoint(x: 13.5, y: 13.5))
        ctx.setLineWidth(2.0)
        ctx.setLineCap(.round)
        ctx.strokePath()
        return img
    }

    private func setupMenu() {
        menu = NSMenu()
        menu.delegate = self

        let appItem = NSMenuItem(
            title: "\(AppConfig.appName) v\(AppConfig.version)",
            action: nil,
            keyEquivalent: ""
        )
        appItem.isEnabled = false
        menu.addItem(appItem)

        menu.addItem(NSMenuItem.separator())

        activateItem = NSMenuItem(
            title: "Activate \(AppConfig.appName)",
            action: #selector(activateAction),
            keyEquivalent: ""
        )
        activateItem.target = self
        menu.addItem(activateItem)

        // Shows the current shortcut; clicking it opens the recorder, already listening.
        shortcutItem = NSMenuItem(title: "Shortcut", action: #selector(recordShortcutAction), keyEquivalent: "")
        shortcutItem.target = self
        menu.addItem(shortcutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(AppConfig.appName)",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// Shows `hotKey` in the menu; `isActive` false marks it as not registered (taken by another app).
    public func updateHotKey(_ hotKey: SavedHotKey, isActive: Bool = true) {

        if isActive {
            activateItem.keyEquivalent = hotKey.keyChar
            activateItem.keyEquivalentModifierMask = hotKey.modifierFlags
        } else {
            activateItem.keyEquivalent = ""
            activateItem.keyEquivalentModifierMask = []
        }

        let status = isActive ? hotKey.displayString : "\(hotKey.displayString) unavailable"
        shortcutItem.title = "Shortcut [\(status)]"
        statusItem.button?.toolTip = "\(AppConfig.appName): Screen Annotation (\(status))"
    }

    @objc private func activateAction() {
        delegate?.statusBarDidRequestActivate()
    }

    @objc private func recordShortcutAction() {
        delegate?.statusBarDidRequestRecordShortcut()
    }

    @objc private func quitAction() {
        delegate?.statusBarDidRequestQuit()
    }
}
