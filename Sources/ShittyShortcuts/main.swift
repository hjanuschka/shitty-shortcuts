import AppKit
import Foundation

let configDir = ("~/.config/shitty-shortcuts" as NSString).expandingTildeInPath
let configPath = configDir + "/init.lua"

// NSMenuItem that runs a Swift closure.
final class ClosureMenuItem: NSMenuItem {
    var handler: (() -> Void)?
    @objc func invoke(_ sender: Any?) { handler?() }
}

var appDelegate: AppDelegate?

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var vm: LuaVM?
    var menu: NSMenu!
    private var luaMenuItems: [NSMenuItem] = []
    private var luaSectionSeparator: NSMenuItem!
    private var profileMenuItem: NSMenuItem!

    // -- profiles --------------------------------------------------------------

    private(set) var profiles: [String] = []
    var profileChangeHandlers: [(String) -> Void] = []

    var activeProfile: String {
        get { UserDefaults.standard.string(forKey: "activeProfile") ?? profiles.first ?? "default" }
        set { UserDefaults.standard.set(newValue, forKey: "activeProfile") }
    }

    func resetProfiles() {
        profiles.removeAll()
        profileChangeHandlers.removeAll()
        profileMenuItem.submenu?.removeAllItems()
        profileMenuItem.isHidden = true
    }

    func addProfile(_ name: String) {
        guard !profiles.contains(name) else { return }
        profiles.append(name)
        profileMenuItem.isHidden = false
        let item = ClosureMenuItem(title: name, action: #selector(ClosureMenuItem.invoke(_:)), keyEquivalent: "")
        item.target = item
        item.handler = { [weak self] in self?.switchProfile(to: name) }
        profileMenuItem.submenu?.addItem(item)
        refreshProfileChecks()
    }

    func switchProfile(to name: String, announce: Bool = true) {
        guard profiles.contains(name) else { return }
        activeProfile = name
        refreshProfileChecks()
        for handler in profileChangeHandlers { handler(name) }
        if announce { Alert.show("profile: " + name, duration: 1.2) }
    }

    private func refreshProfileChecks() {
        for case let item as NSMenuItem in profileMenuItem.submenu?.items ?? [] {
            item.state = item.title == activeProfile ? .on : .off
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "💩⌨️"

        let menu = NSMenu()
        self.menu = menu

        profileMenuItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let profileMenu = NSMenu(title: "Profile")
        profileMenuItem.submenu = profileMenu
        menu.addItem(profileMenuItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Edit Config", action: #selector(editConfig), keyEquivalent: "e"))
        luaSectionSeparator = NSMenuItem.separator()
        menu.addItem(luaSectionSeparator)

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

    // -- lua-scriptable menubar items -----------------------------------------

    func clearLuaMenuItems() {
        for item in luaMenuItems { menu.removeItem(item) }
        luaMenuItems.removeAll()
    }

    func addLuaMenuItem(title: String, handler: @escaping () -> Void) -> ClosureMenuItem {
        let item = ClosureMenuItem(title: title, action: #selector(ClosureMenuItem.invoke(_:)), keyEquivalent: "")
        item.target = item
        item.handler = handler
        let index = menu.index(of: luaSectionSeparator) + 1 + luaMenuItems.count
        menu.insertItem(item, at: index)
        luaMenuItems.append(item)
        return item
    }

    func setStatusTitle(_ title: String) {
        statusItem.button?.title = title
    }

    func loadConfig() {
        Hotkeys.shared.unbindAll()
        clearLuaMenuItems()
        resetProfiles()
        statusItem.button?.title = "\u{1F4A9}\u{2328}\u{FE0F}"
        vm = LuaVM()
        API.register(vm: vm!)

        if !FileManager.default.fileExists(atPath: configPath) {
            try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
            Alert.show("no config at \(configPath)", duration: 4)
            return
        }
        if vm!.doFile(configPath) {
            // fire the change handlers once so the config syncs to the
            // persisted profile right after load
            if !profiles.isEmpty {
                switchProfile(to: activeProfile, announce: false)
            }
            Alert.show("\u{1F4A9}\u{2328}\u{FE0F} config loaded", duration: 1.5)
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
appDelegate = delegate
app.delegate = delegate
app.run()
