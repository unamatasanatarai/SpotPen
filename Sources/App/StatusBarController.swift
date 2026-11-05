import Cocoa

public enum StatusBarIconMode: String, CaseIterable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"
    
    public var title: String {
        switch self {
        case .auto: return "Auto (Match System)"
        case .light: return "Light Mode (Dark Icon)"
        case .dark: return "Dark Mode (Light Icon)"
        }
    }
}

public protocol StatusBarControllerDelegate: AnyObject {
    func statusBarDidRequestToggle()
    func statusBarDidRequestClear()
    func statusBarDidRequestUndo()
    func statusBarDidRequestQuit()
    func statusBarDidSelectHotKey(_ hotKey: SavedHotKey)
    func statusBarDidRequestRecordShortcut()
}

public final class StatusBarController: NSObject, NSMenuDelegate {
    public weak var delegate: StatusBarControllerDelegate?
    
    private static let iconModeKey = "StatusBarIconMode"
    
    public static var currentIconMode: StatusBarIconMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: iconModeKey),
               let mode = StatusBarIconMode(rawValue: raw) {
                return mode
            }
            return .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: iconModeKey)
        }
    }
    
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var toggleItem: NSMenuItem!
    private var shortcutSubmenuItem: NSMenuItem!
    private var shortcutMenu: NSMenu!
    private var iconSubmenuItem: NSMenuItem!
    private var iconMenu: NSMenu!
    
    private var currentHotKey: SavedHotKey = .defaultHotKey
    public private(set) var currentIconMode: StatusBarIconMode = .auto
    
    public override init() {
        super.init()
        self.currentHotKey = SavedHotKey.current
        self.currentIconMode = Self.currentIconMode
        setupStatusItem()
        setupMenu()
    }
    
    public var currentMenu: NSMenu {
        return menu
    }
    
    public var currentStatusItem: NSStatusItem {
        return statusItem
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon()
    }
    
    public func updateStatusItemIcon() {
        if let button = statusItem.button {
            button.image = Self.loadIcon(for: currentIconMode)
            button.imagePosition = .imageOnly
            button.toolTip = "\(AppConfig.appName): Screen Annotation (\(currentHotKey.displayString))"
        }
    }
    
    public static func loadIcon(for mode: StatusBarIconMode) -> NSImage {
        let resourceName: String
        let isTemplate: Bool
        
        switch mode {
        case .auto:
            resourceName = "StatusBarIcon"
            isTemplate = true
        case .light:
            resourceName = "StatusBarIcon_Light"
            isTemplate = false
        case .dark:
            resourceName = "StatusBarIcon_Dark"
            isTemplate = false
        }
        
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        var loaded = false
        
        // 1. Try loading from main bundle
        if let url1x = Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let rep1x = NSImageRep(contentsOf: url1x) {
            rep1x.size = size
            image.addRepresentation(rep1x)
            loaded = true
        }
        if let url2x = Bundle.main.url(forResource: "\(resourceName)@2x", withExtension: "png"),
           let rep2x = NSImageRep(contentsOf: url2x) {
            rep2x.size = size
            image.addRepresentation(rep2x)
            loaded = true
        }
        
        // 2. Fallback to local Resources/ folder (for testing or dev mode)
        if !loaded {
            let localPath1x = "Resources/\(resourceName).png"
            let localPath2x = "Resources/\(resourceName)@2x.png"
            if FileManager.default.fileExists(atPath: localPath1x),
               let rep1x = NSImageRep(contentsOfFile: localPath1x) {
                rep1x.size = size
                image.addRepresentation(rep1x)
                loaded = true
            }
            if FileManager.default.fileExists(atPath: localPath2x),
               let rep2x = NSImageRep(contentsOfFile: localPath2x) {
                rep2x.size = size
                image.addRepresentation(rep2x)
                loaded = true
            }
        }
        
        // 3. Fallback programmatic icon if files are missing
        if !loaded {
            return renderFallbackIcon(for: mode)
        }
        
        image.isTemplate = isTemplate
        return image
    }
    
    public static func renderPenIcon() -> NSImage {
        return loadIcon(for: currentIconMode)
    }
    
    private static func renderFallbackIcon(for mode: StatusBarIconMode) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus()
            return img
        }
        
        ctx.saveGState()
        let strokeColor: CGColor
        switch mode {
        case .auto, .light:
            strokeColor = NSColor.black.cgColor
        case .dark:
            strokeColor = NSColor.white.cgColor
        }
        
        // Outer circle
        ctx.addArc(center: CGPoint(x: 9, y: 9), radius: 6.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setStrokeColor(strokeColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        
        // Angled pen
        ctx.move(to: CGPoint(x: 4.5, y: 4.5))
        ctx.addLine(to: CGPoint(x: 13.5, y: 13.5))
        ctx.setLineWidth(2.0)
        ctx.setLineCap(.round)
        ctx.strokePath()
        
        ctx.restoreGState()
        img.unlockFocus()
        img.isTemplate = (mode == .auto)
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
        
        toggleItem = NSMenuItem(
            title: "Toggle \(AppConfig.appName)",
            action: #selector(toggleAction),
            keyEquivalent: currentHotKey.keyChar
        )
        toggleItem.keyEquivalentModifierMask = currentHotKey.modifierFlags
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        // Shortcut configuration submenu
        shortcutSubmenuItem = NSMenuItem(title: "Shortcut (\(currentHotKey.displayString))", action: nil, keyEquivalent: "")
        shortcutMenu = NSMenu()
        buildShortcutSubmenu()
        shortcutSubmenuItem.submenu = shortcutMenu
        menu.addItem(shortcutSubmenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let clearItem = NSMenuItem(
            title: "Clear Screen",
            action: #selector(clearAction),
            keyEquivalent: "c"
        )
        clearItem.keyEquivalentModifierMask = []
        clearItem.target = self
        menu.addItem(clearItem)
        
        let undoItem = NSMenuItem(
            title: "Undo",
            action: #selector(undoAction),
            keyEquivalent: "z"
        )
        undoItem.keyEquivalentModifierMask = [.command]
        undoItem.target = self
        menu.addItem(undoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Status Bar Icon appearance submenu (Auto / Light Mode / Dark Mode)
        iconSubmenuItem = NSMenuItem(title: "Status Bar Icon", action: nil, keyEquivalent: "")
        iconMenu = NSMenu()
        buildIconSubmenu()
        iconSubmenuItem.submenu = iconMenu
        menu.addItem(iconSubmenuItem)
        
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
    
    private func buildIconSubmenu() {
        iconMenu.removeAllItems()
        
        for mode in StatusBarIconMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(iconModeSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode
            item.state = (mode == currentIconMode) ? .on : .off
            iconMenu.addItem(item)
        }
    }
    
    @objc private func iconModeSelected(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? StatusBarIconMode else { return }
        setIconMode(mode)
    }
    
    public func setIconMode(_ mode: StatusBarIconMode) {
        self.currentIconMode = mode
        Self.currentIconMode = mode
        updateStatusItemIcon()
        buildIconSubmenu()
    }
    
    private func buildShortcutSubmenu() {
        shortcutMenu.removeAllItems()
        
        for preset in SavedHotKey.presets {
            let item = NSMenuItem(
                title: preset.displayString,
                action: #selector(presetClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset
            item.state = (preset == currentHotKey) ? .on : .off
            shortcutMenu.addItem(item)
        }
        
        shortcutMenu.addItem(NSMenuItem.separator())
        
        let recordItem = NSMenuItem(
            title: "Record Custom Shortcut...",
            action: #selector(recordShortcutAction),
            keyEquivalent: ""
        )
        recordItem.target = self
        shortcutMenu.addItem(recordItem)
    }
    
    public func updateHotKey(_ hotKey: SavedHotKey) {
        self.currentHotKey = hotKey
        
        toggleItem.keyEquivalent = hotKey.keyChar
        toggleItem.keyEquivalentModifierMask = hotKey.modifierFlags
        
        shortcutSubmenuItem.title = "Shortcut (\(hotKey.displayString))"
        if let button = statusItem.button {
            button.toolTip = "\(AppConfig.appName): Screen Annotation (\(hotKey.displayString))"
        }
        
        buildShortcutSubmenu()
    }
    
    public func updateOverlayVisibility(isVisible: Bool) {
        toggleItem.title = isVisible ? "Hide \(AppConfig.appName)" : "Toggle \(AppConfig.appName)"
    }
    
    @objc private func toggleAction() {
        delegate?.statusBarDidRequestToggle()
    }
    
    @objc private func presetClicked(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? SavedHotKey else { return }
        updateHotKey(preset)
        delegate?.statusBarDidSelectHotKey(preset)
    }
    
    @objc private func recordShortcutAction() {
        delegate?.statusBarDidRequestRecordShortcut()
    }
    
    @objc private func clearAction() {
        delegate?.statusBarDidRequestClear()
    }
    
    @objc private func undoAction() {
        delegate?.statusBarDidRequestUndo()
    }
    
    @objc private func quitAction() {
        delegate?.statusBarDidRequestQuit()
    }
}
