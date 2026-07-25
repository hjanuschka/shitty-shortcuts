import AppKit
import Foundation

let configDir = ("~/.config/shitty-shortcuts" as NSString).expandingTildeInPath
let configPath = configDir + "/init.lua"

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var vm: LuaVM?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "💩⌨️"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Edit Config", action: #selector(editConfig), keyEquivalent: "e"))
        menu.addItem(.separator())

        let micItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let micMenu = NSMenu(title: "Microphone")
        micMenu.delegate = self
        micItem.submenu = micMenu
        menu.addItem(micItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit shitty-shortcuts", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu

        loadConfig()
    }

    func loadConfig() {
        Hotkeys.shared.unbindAll()
        vm = LuaVM()
        API.register(vm: vm!)

        if !FileManager.default.fileExists(atPath: configPath) {
            try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
            Alert.show("no config at \(configPath)", duration: 4)
            return
        }
        if vm!.doFile(configPath) {
            Alert.show("💩⌨️ config loaded", duration: 1.5)
        }
    }

    @objc func reloadConfig() { loadConfig() }

    @objc func editConfig() {
        EditorWindowController.open(path: configPath) { [weak self] in
            self?.loadConfig()
        }
    }

    // -- microphone submenu ---------------------------------------------------

    @objc func selectMic(_ sender: NSMenuItem) {
        if sender.representedObject == nil {
            UserDefaults.standard.removeObject(forKey: "micDevice")
        } else if let name = sender.representedObject as? String {
            UserDefaults.standard.set(name, forKey: "micDevice")
        }
        Alert.show("\u{1F399} mic: " + (sender.representedObject as? String ?? "automatic (config rules)"), duration: 1.5)
    }
}

extension AppDelegate: NSMenuDelegate {
    // Rebuild the mic list every time the submenu opens (devices come and go).
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Microphone" else { return }
        menu.removeAllItems()
        let chosen = UserDefaults.standard.string(forKey: "micDevice")

        let auto = NSMenuItem(title: "Automatic (config rules)", action: #selector(selectMic(_:)), keyEquivalent: "")
        auto.target = self
        auto.state = chosen == nil ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())

        for name in AudioDevices.inputDeviceNames() {
            let item = NSMenuItem(title: name, action: #selector(selectMic(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = name == chosen ? .on : .off
            menu.addItem(item)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
