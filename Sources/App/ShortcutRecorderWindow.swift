import AppKit

public final class ShortcutRecordContentView: NSView {
    /// Applies the recorded shortcut; returns the error to show if it could not be registered.
    public var onRecorded: ((SavedHotKey) -> Result<Void, ShortcutError>)?
    /// Called once the success confirmation has been shown.
    public var onFinished: (() -> Void)?
    public var onCancel: (() -> Void)?
    
    private let titleLabel = NSTextField(labelWithString: "Change Activation Shortcut")
    private let promptLabel = NSTextField(labelWithString: "Press desired shortcut combination...")
    private let shortcutBox = NSBox()
    private let shortcutLabel = NSTextField(labelWithString: "Type shortcut...")
    private let tipLabel = NSTextField(labelWithString: "Requires ⌘ or ⌃, or an F-key (Esc to cancel)")
    
    public override var acceptsFirstResponder: Bool {
        return true
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        wantsLayer = true
        
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        shortcutBox.boxType = .custom
        shortcutBox.cornerRadius = 8.0
        shortcutBox.borderWidth = 1.5
        shortcutBox.borderColor = NSColor.systemBlue
        shortcutBox.fillColor = NSColor.black.withAlphaComponent(0.2)
        shortcutBox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shortcutBox)
        
        shortcutLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        shortcutLabel.alignment = .center
        shortcutLabel.textColor = NSColor.labelColor
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutBox.contentView?.addSubview(shortcutLabel)
        
        promptLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        promptLabel.textColor = NSColor.secondaryLabelColor
        promptLabel.alignment = .center
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(promptLabel)
        
        tipLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        tipLabel.textColor = NSColor.tertiaryLabelColor
        tipLabel.alignment = .center
        tipLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tipLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            
            shortcutBox.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            shortcutBox.centerXAnchor.constraint(equalTo: centerXAnchor),
            shortcutBox.widthAnchor.constraint(equalToConstant: 240),
            shortcutBox.heightAnchor.constraint(equalToConstant: 48),
            
            shortcutLabel.centerXAnchor.constraint(equalTo: shortcutBox.centerXAnchor),
            shortcutLabel.centerYAnchor.constraint(equalTo: shortcutBox.centerYAnchor),
            
            promptLabel.topAnchor.constraint(equalTo: shortcutBox.bottomAnchor, constant: 10),
            promptLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            
            tipLabel.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            tipLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }
    
    public func reset(with current: SavedHotKey) {
        shortcutLabel.stringValue = current.displayString
        promptLabel.stringValue = "Press new key combination to change..."
        shortcutBox.borderColor = NSColor.systemBlue
    }
    
    public override func keyDown(with event: NSEvent) {
        // Esc: Cancel
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        
        switch SavedHotKey.parse(event: event) {
        case .success(let newHotKey):
            shortcutLabel.stringValue = newHotKey.displayString
            if case .failure(let error) = onRecorded?(newHotKey) ?? .success(()) {
                showError(error)
                return
            }
            shortcutBox.borderColor = NSColor.systemGreen
            promptLabel.stringValue = "Saved!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.onFinished?()
            }
        case .failure(let error):
            showError(error)
        }
    }
    
    private func showError(_ error: ShortcutError) {
        shortcutBox.borderColor = NSColor.systemRed
        promptLabel.stringValue = error.message
        NSSound.beep()
    }
}

public final class ShortcutRecorderWindow: NSPanel {
    public static let shared = ShortcutRecorderWindow()
    public var onHotKeyRecorded: ((SavedHotKey) -> Result<Void, ShortcutError>)?
    
    private var recordView: ShortcutRecordContentView!
    
    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled, .closable, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        self.title = "SpotPen Shortcut"
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.center()
        
        recordView = ShortcutRecordContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        recordView.onRecorded = { [weak self] hotKey in
            return self?.onHotKeyRecorded?(hotKey) ?? .success(())
        }
        recordView.onFinished = { [weak self] in
            self?.orderOut(nil)
        }
        recordView.onCancel = { [weak self] in
            self?.orderOut(nil)
        }
        self.contentView = recordView
    }
    
    public func show(currentHotKey: SavedHotKey) {
        recordView.reset(with: currentHotKey)
        self.center()
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.makeFirstResponder(recordView)
    }
}

