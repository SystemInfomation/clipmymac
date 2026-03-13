import Foundation
import AppKit
import Carbon
import OSLog

private let logger = Logger(subsystem: "com.clipmaclocal", category: "HotkeyManager")

// MARK: - Hotkey Configuration

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultSaveClip = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0   { parts.append("⌘") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(shiftKey) != 0  { parts.append("⇧") }

        if let keyStr = keyCodeToString(keyCode) {
            parts.append(keyStr.uppercased())
        }
        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt32) -> String? {
        let mapping: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B",
            UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
            UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
            UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N",
            UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
            UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
            UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        ]
        return mapping[code]
    }
}

// MARK: - Hotkey Manager

/// Registers and handles global hotkeys using Carbon Event Manager.
final class HotkeyManager {

    static let shared = HotkeyManager()

    var onSaveClip: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var saveClipConfig: HotkeyConfig = .defaultSaveClip
    private var eventHandler: EventHandlerRef?

    private init() {}

    // MARK: - Register

    func register(saveClipHotkey: HotkeyConfig) {
        self.saveClipConfig = saveClipHotkey
        unregister()
        installEventHandler()
        registerHotkey(config: saveClipHotkey, id: 1)
    }

    // MARK: - Unregister

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    // MARK: - Private

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event,
                                  OSType(kEventParamDirectObject),
                                  OSType(typeEventHotKeyID),
                                  nil,
                                  MemoryLayout<EventHotKeyID>.size,
                                  nil,
                                  &hotKeyID)
                if hotKeyID.id == 1 {
                    DispatchQueue.main.async { manager.onSaveClip?() }
                }
                return noErr
            },
            1, &eventSpec, selfPtr, &eventHandler
        )
    }

    private func registerHotkey(config: HotkeyConfig, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x434D4C43), id: id) // 'CMLC'
        RegisterEventHotKey(config.keyCode,
                            config.modifiers,
                            hotKeyID,
                            GetApplicationEventTarget(),
                            0,
                            &hotKeyRef)
        logger.info("Registered hotkey: \(config.displayString)")
    }
}
