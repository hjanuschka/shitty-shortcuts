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
    // Two sources merge: config-declared (ss.profile.add) and user-created
    // (menubar "New Profile...", persisted in UserDefaults).

    private var luaProfiles: [String] = []
    var profileChangeHandlers: [(String) -> Void] = []

    private var userProfiles: [String] {
        get { UserDefaults.standard.stringArray(forKey: "userProfiles") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "userProfiles") }
    }

    var profiles: [String] {
        var seen = Set<String>()
        return (luaProfiles + userProfiles).filter { seen.insert($0).inserted }
    }

    var activeProfile: String {
        get { UserDefaults.standard.string(forKey: "activeProfile") ?? profiles.first ?? "default" }
        set { UserDefaults.standard.set(newValue, forKey: "activeProfile") }
    }

    func resetProfiles() {
        luaProfiles.removeAll()
        profileChangeHandlers.removeAll()
    }

    func addProfile(_ name: String) {
        guard !luaProfiles.contains(name) else { return }
        luaProfiles.append(name)
    }

    func switchProfile(to name: String, announce: Bool = true) {
        guard profiles.contains(name) else { return }
        activeProfile = name
        for handler in profileChangeHandlers { handler(name) }
        if announce { Alert.show("profile: " + name, duration: 1.2) }
    }

    @objc func newProfileAction() {
        let alert = NSAlert()
        alert.messageText = "New Profile"
        alert.informativeText = "Name for the new profile. Your Lua config can dispatch on it via ss.profile.current()."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "e.g. meeting, streaming, gaming"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !profiles.contains(name) else { return }
        userProfiles.append(name)
        switchProfile(to: name)
    }

    @objc func deleteProfileAction() {
        let name = activeProfile
        guard userProfiles.contains(name) else {
            Alert.show("'" + name + "' is defined by the config - remove it there")
            return
        }
        userProfiles.removeAll { $0 == name }
        if let fallback = profiles.first { switchProfile(to: fallback) }
    }

    @objc func renameProfileAction() {
        let oldName = activeProfile
        guard userProfiles.contains(oldName) else {
            Alert.show("'" + oldName + "' is defined by the config - rename it there")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Rename Profile"
        alert.informativeText = "New name for \u{201C}" + oldName + "\u{201D}. Remember to update any ss.profile.current() checks in your config."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = oldName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != oldName, !profiles.contains(newName) else { return }
        userProfiles = userProfiles.map { $0 == oldName ? newName : $0 }
        switchProfile(to: newName)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "💩⌨️"

        let menu = NSMenu()
        self.menu = menu

        profileMenuItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let profileMenu = NSMenu(title: "Profile")
        profileMenu.delegate = self
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
        API.terminateAllTasks()
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
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == "Profile" {
            menu.removeAllItems()
            for name in profiles {
                let item = ClosureMenuItem(title: name, action: #selector(ClosureMenuItem.invoke(_:)), keyEquivalent: "")
                item.target = item
                item.handler = { [weak self] in self?.switchProfile(to: name) }
                item.state = name == activeProfile ? .on : .off
                menu.addItem(item)
            }
            if !profiles.isEmpty { menu.addItem(.separator()) }
            let newItem = NSMenuItem(title: "New Profile...", action: #selector(newProfileAction), keyEquivalent: "")
            newItem.target = self
            menu.addItem(newItem)
            if userProfiles.contains(activeProfile) {
                let ren = NSMenuItem(title: "Rename \u{201C}" + activeProfile + "\u{201D}...", action: #selector(renameProfileAction), keyEquivalent: "")
                ren.target = self
                menu.addItem(ren)
                let del = NSMenuItem(title: "Delete \u{201C}" + activeProfile + "\u{201D}", action: #selector(deleteProfileAction), keyEquivalent: "")
                del.target = self
                menu.addItem(del)
            }
            return
        }
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
