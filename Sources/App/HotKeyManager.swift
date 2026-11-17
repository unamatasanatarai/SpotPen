import Cocoa
import Carbon

public enum ShortcutError: Error, Equatable {
    /// The key has no display name / is not supported as a hotkey.
    case unsupportedKey
    /// Global hotkeys swallow the keystroke system-wide, so a Shift- or Option-only combination would
    /// block typing (capital letters, accented characters). ⌘ or ⌃ is required unless it is an F-key.
    case needsCommandOrControl
    /// The system refused the registration (reserved, or registered exclusively elsewhere).
    /// Note: macOS does not report ordinary registrations by other apps, so this cannot detect every clash.
    case unavailable(OSStatus)

    public var message: String {
        switch self {
        case .unsupportedKey:
            return "That key can't be used as a shortcut"
        case .needsCommandOrControl:
            return "Include ⌘ or ⌃ (or use an F-key)"
        case .unavailable:
            return "macOS refused this shortcut"
        }
    }
}

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

    static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
    ]

    public var isFunctionKey: Bool {
        return Self.functionKeyCodes.contains(Int(keyCode))
    }

    /// Whether this combination is safe to grab system-wide (see `ShortcutError.needsCommandOrControl`).
    public var isAllowedAsGlobalShortcut: Bool {
        let commandOrControl = UInt32(cmdKey | controlKey)
        return (carbonModifiers & commandOrControl) != 0 || isFunctionKey
    }

    /// Same physical key and modifiers.
    public func isSameCombination(as other: SavedHotKey) -> Bool {
        return keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
    }

    public static let defaultHotKey = SavedHotKey(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(controlKey),
        displayString: "⌃D",
        keyChar: "d",
        modifierMaskRaw: NSEvent.ModifierFlags([.control]).rawValue
    )

    /// ⌃⌥⌘ combinations are rarely bound by apps, unlike ⌘⇧S (Save As) or ⌥Space (non-breaking space).
    public static let presets: [SavedHotKey] = [
        defaultHotKey,
        SavedHotKey(
            keyCode: UInt32(kVK_ANSI_A),
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
            displayString: "⌃⌥⌘A",
            keyChar: "a",
            modifierMaskRaw: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
        ),
        SavedHotKey(
            keyCode: UInt32(kVK_ANSI_P),
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
            displayString: "⌃⌥⌘P",
            keyChar: "p",
            modifierMaskRaw: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
        ),
        SavedHotKey(
            keyCode: UInt32(kVK_ANSI_D),
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
            displayString: "⌃⌥⌘D",
            keyChar: "d",
            modifierMaskRaw: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
        ),
        SavedHotKey(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
            displayString: "⌃⌥⌘Space",
            keyChar: " ",
            modifierMaskRaw: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
        )
    ]

    static let defaultsKey = "SpotPen.ToggleHotKey"

    /// The saved shortcut, or the default when none is saved or the saved one is no longer allowed.
    public static func load(from defaults: UserDefaults) -> SavedHotKey {
        guard let data = defaults.data(forKey: defaultsKey),
              let hotKey = try? JSONDecoder().decode(SavedHotKey.self, from: data),
              hotKey.isAllowedAsGlobalShortcut else {
            return .defaultHotKey
        }
        return hotKey
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Builds a shortcut from a key event and checks that it is safe to register globally.
    public static func parse(event: NSEvent) -> Result<SavedHotKey, ShortcutError> {
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

        let charName = keyString(for: event.keyCode)
        guard charName != "?" else { return .failure(.unsupportedKey) }

        var display = ""
        if (carbonMods & UInt32(controlKey)) != 0 { display += "⌃" }
        if (carbonMods & UInt32(optionKey)) != 0 { display += "⌥" }
        if (carbonMods & UInt32(shiftKey)) != 0 { display += "⇧" }
        if (carbonMods & UInt32(cmdKey)) != 0 { display += "⌘" }
        display += charName

        // Menu key equivalents need the unshifted character; charactersIgnoringModifiers keeps Shift.
        let keyChar: String
        if functionKeyCodes.contains(Int(event.keyCode)) {
            keyChar = event.charactersIgnoringModifiers ?? ""
        } else if Int(event.keyCode) == kVK_Space {
            keyChar = " "
        } else {
            keyChar = charName.count == 1 ? charName.lowercased() : (event.charactersIgnoringModifiers?.lowercased() ?? "")
        }

        let hotKey = SavedHotKey(
            keyCode: keyCode,
            carbonModifiers: carbonMods,
            displayString: display,
            keyChar: keyChar,
            modifierMaskRaw: nsMods.rawValue
        )
        guard hotKey.isAllowedAsGlobalShortcut else { return .failure(.needsCommandOrControl) }
        return .success(hotKey)
    }

    public static func from(event: NSEvent) -> SavedHotKey? {
        return try? parse(event: event).get()
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

    private static let signature = OSType(0x5343524E) // 'SCRN'

    private let defaults: UserDefaults
    private var action: HotKeyAction?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// The combination currently registered (or the one that was attempted if `isRegistered` is false).
    public private(set) var currentHotKey: SavedHotKey

    /// False when the system refused every shortcut tried at launch.
    public var isRegistered: Bool {
        return hotKeyRef != nil
    }

    public init(defaults: UserDefaults = .standard, action: @escaping HotKeyAction) {
        self.defaults = defaults
        self.action = action
        let saved = SavedHotKey.load(from: defaults)
        self.currentHotKey = saved
        installHandler()

        // Fall back to the default for this session if the saved shortcut is taken; the saved choice is kept.
        if case .failure = activate(saved), !saved.isSameCombination(as: .defaultHotKey) {
            _ = activate(.defaultHotKey)
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { (_, event, userData) -> OSStatus in
            guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == HotKeyManager.signature else {
                return OSStatus(eventNotHandledErr)
            }

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

    /// Registers `hotKey` and saves it. On failure the previous shortcut stays registered and saved.
    @discardableResult
    public func registerHotKey(_ hotKey: SavedHotKey) -> Result<Void, ShortcutError> {
        guard hotKey.isAllowedAsGlobalShortcut else { return .failure(.needsCommandOrControl) }
        let result = activate(hotKey)
        if case .success = result {
            hotKey.save(to: defaults)
            onHotKeyChanged?(hotKey)
        }
        return result
    }

    /// Registers the new combination first and only then releases the old one.
    private func activate(_ hotKey: SavedHotKey) -> Result<Void, ShortcutError> {
        if hotKeyRef != nil, hotKey.isSameCombination(as: currentHotKey) {
            currentHotKey = hotKey
            return .success(())
        }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let createdRef = ref else {
            NSLog("[SpotPen] Could not register global hotkey %@: status %d", hotKey.displayString, status)
            return .failure(.unavailable(status))
        }

        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
        }
        hotKeyRef = createdRef
        currentHotKey = hotKey
        NSLog("[SpotPen] Registered global activation hotkey: %@", hotKey.displayString)
        return .success(())
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
