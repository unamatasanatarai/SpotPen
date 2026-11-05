import Cocoa
import Carbon

public struct SavedHotKey: Codable, Equatable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var displayString: String
    public var keyChar: String
    public var modifierMaskRaw: UInt
    
    public init(
        keyCode: UInt32,
        carbonModifiers: UInt32,
        displayString: String,
        keyChar: String,
        modifierMaskRaw: UInt
    ) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.displayString = displayString
        self.keyChar = keyChar
        self.modifierMaskRaw = modifierMaskRaw
    }
    
    public var modifierFlags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: modifierMaskRaw)
    }
    
    public static let defaultHotKey = SavedHotKey(
        keyCode: UInt32(kVK_ANSI_A),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        displayString: "⌘⇧A",
        keyChar: "a",
        modifierMaskRaw: NSEvent.ModifierFlags([.command, .shift]).rawValue
    )
    
    public static let presets: [SavedHotKey] = [
        defaultHotKey,
        SavedHotKey(
            keyCode: UInt32(kVK_ANSI_P),
            carbonModifiers: UInt32(cmdKey | shiftKey),
            displayString: "⌘⇧P",
            keyChar: "p",
            modifierMaskRaw: NSEvent.ModifierFlags([.command, .shift]).rawValue
        ),
        SavedHotKey(
            keyCode: UInt32(kVK_ANSI_S),
            carbonModifiers: UInt32(cmdKey | shiftKey),
            displayString: "⌘⇧S",
            keyChar: "s",
            modifierMaskRaw: NSEvent.ModifierFlags([.command, .shift]).rawValue
        ),
        SavedHotKey(
            keyCode: UInt32(kVK_ANSI_D),
            carbonModifiers: UInt32(cmdKey | shiftKey),
            displayString: "⌘⇧D",
            keyChar: "d",
            modifierMaskRaw: NSEvent.ModifierFlags([.command, .shift]).rawValue
        ),
        SavedHotKey(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(cmdKey | optionKey),
            displayString: "⌘⌥Space",
            keyChar: " ",
            modifierMaskRaw: NSEvent.ModifierFlags([.command, .option]).rawValue
        ),
        SavedHotKey(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(optionKey),
            displayString: "⌥Space",
            keyChar: " ",
            modifierMaskRaw: NSEvent.ModifierFlags([.option]).rawValue
        )
    ]
    
    public static var current: SavedHotKey {
        get {
            guard let data = UserDefaults.standard.data(forKey: "SpotPen.ToggleHotKey"),
                  let hotKey = try? JSONDecoder().decode(SavedHotKey.self, from: data) else {
                return .defaultHotKey
            }
            return hotKey
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "SpotPen.ToggleHotKey")
            }
        }
    }
    
    public static func from(event: NSEvent) -> SavedHotKey? {
        let keyCode = UInt32(event.keyCode)
        var carbonMods: UInt32 = 0
        var nsMods = NSEvent.ModifierFlags()
        
        if event.modifierFlags.contains(.control) {
            carbonMods |= UInt32(controlKey)
            nsMods.insert(.control)
        }
        if event.modifierFlags.contains(.option) {
            carbonMods |= UInt32(optionKey)
            nsMods.insert(.option)
        }
        if event.modifierFlags.contains(.shift) {
            carbonMods |= UInt32(shiftKey)
            nsMods.insert(.shift)
        }
        if event.modifierFlags.contains(.command) {
            carbonMods |= UInt32(cmdKey)
            nsMods.insert(.command)
        }
        
        let isFKey = (event.keyCode >= 122 && event.keyCode <= 130) || (event.keyCode >= 96 && event.keyCode <= 101)
        if carbonMods == 0 && !isFKey {
            return nil
        }
        
        let charName = keyString(for: event.keyCode)
        guard charName != "?" else { return nil }
        
        var display = ""
        if (carbonMods & UInt32(controlKey)) != 0 { display += "⌃" }
        if (carbonMods & UInt32(optionKey)) != 0 { display += "⌥" }
        if (carbonMods & UInt32(shiftKey)) != 0 { display += "⇧" }
        if (carbonMods & UInt32(cmdKey)) != 0 { display += "⌘" }
        display += charName
        
        let keyChar = event.charactersIgnoringModifiers?.lowercased() ?? charName.lowercased()
        
        return SavedHotKey(
            keyCode: keyCode,
            carbonModifiers: carbonMods,
            displayString: display,
            keyChar: keyChar,
            modifierMaskRaw: nsMods.rawValue
        )
    }
    
    public static func keyString(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "?"
        }
    }
}

public final class HotKeyManager {
    public typealias HotKeyAction = () -> Void
    
    public var onHotKeyChanged: ((SavedHotKey) -> Void)?
    
    private var action: HotKeyAction?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    
    public private(set) var currentHotKey: SavedHotKey = .defaultHotKey
    
    public init(action: @escaping HotKeyAction) {
        self.action = action
        self.currentHotKey = SavedHotKey.current
        installHandler()
        registerHotKey(currentHotKey)
    }
    
    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        let callback: EventHandlerUPP = { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            
            DispatchQueue.main.async {
                manager.action?()
            }
            return noErr
        }
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        
        if status != noErr {
            NSLog("[SpotPen] Failed to install Carbon event handler: status %d", status)
        }
    }
    
    public func registerHotKey(_ hotKey: SavedHotKey) {
        SavedHotKey.current = hotKey
        self.currentHotKey = hotKey
        registerHotKey(keyCode: hotKey.keyCode, modifiers: hotKey.carbonModifiers, id: 1)
        onHotKeyChanged?(hotKey)
    }
    
    public func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5343524E), id: id) // 'SCRN'
        
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        
        if status == noErr, let createdRef = ref {
            hotKeyRef = createdRef
            NSLog("[SpotPen] Registered global toggle hotkey: %@ (status: %d)", currentHotKey.displayString, status)
        } else {
            NSLog("[SpotPen] Could not register global hotkey: status %d", status)
        }
    }
    
    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
}
