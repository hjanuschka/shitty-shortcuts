import Carbon
import Foundation

// Global hotkeys via Carbon RegisterEventHotKey - no accessibility
// permission needed, and we get separate pressed/released events.
final class Hotkeys {
    static let shared = Hotkeys()

    struct Binding {
        let pressed: () -> Void
        let released: (() -> Void)?
    }

    private var bindings: [UInt32: Binding] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var nextId: UInt32 = 1
    private var handlerInstalled = false

    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46, "return": 36, "tab": 48, "space": 49,
        "escape": 53, "f19": 80,
    ]

    static func carbonModifiers(_ mods: [String]) -> UInt32 {
        var flags: UInt32 = 0
        for m in mods {
            switch m.lowercased() {
            case "cmd", "command": flags |= UInt32(cmdKey)
            case "alt", "opt", "option": flags |= UInt32(optionKey)
            case "ctrl", "control": flags |= UInt32(controlKey)
            case "shift": flags |= UInt32(shiftKey)
            default: break
            }
        }
        return flags
    }

    func bind(mods: [String], key: String, pressed: @escaping () -> Void, released: (() -> Void)?) {
        installHandlerIfNeeded()
        guard let keyCode = Hotkeys.keyCodes[key.lowercased()] else {
            Alert.show("shitty-shortcuts: unknown key '\(key)'")
            return
        }
        let id = nextId
        nextId += 1
        bindings[id] = Binding(pressed: pressed, released: released)

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5353_4B59), id: id) // "SSKY"
        RegisterEventHotKey(keyCode, Hotkeys.carbonModifiers(mods), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
        hotKeyRefs.append(hotKeyRef)
    }

    func unbindAll() {
        for ref in hotKeyRefs { if let ref { UnregisterEventHotKey(ref) } }
        hotKeyRefs.removeAll()
        bindings.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let kind = GetEventKind(event)
            DispatchQueue.main.async {
                guard let binding = Hotkeys.shared.bindings[hotKeyID.id] else { return }
                if kind == UInt32(kEventHotKeyPressed) {
                    binding.pressed()
                } else if kind == UInt32(kEventHotKeyReleased) {
                    binding.released?()
                }
            }
            return noErr
        }, eventTypes.count, &eventTypes, nil, nil)
    }
}
