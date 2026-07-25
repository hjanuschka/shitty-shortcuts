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
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
