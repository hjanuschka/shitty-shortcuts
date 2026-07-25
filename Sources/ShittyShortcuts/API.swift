import AppKit
import CLua
import Foundation

// Builds the `ss` global (aliased as `hs` for Hammerspoon compatibility).
// Only the API subset used by the keypad config is implemented.
enum API {
    private static var tasks: [Int: Process] = [:]
    private static var taskOutputs: [Int: Pipe] = [:]
    private static var nextTaskId = 0
    private static var timers: [Int: Timer] = [:]
    private static var nextTimerId = 0

    static func register(vm: LuaVM) {
        let L = vm.L
        lua_createtable(L, 0, 12)

        // ---- ss.hotkey ----
        vm.beginTable()
        vm.setField("bind") { vm in
            let L = vm.L
            let mods = vm.stringArray(at: 1)
            guard let key = vm.string(at: 2) else { return 0 }
            lua_pushvalue(L, 3)
            let pressedRef = vm.ref()
            var releasedRef: Int32? = nil
            if lua_type(L, 4) == LUA_TFUNCTION {
                lua_pushvalue(L, 4)
                releasedRef = vm.ref()
            }
            Hotkeys.shared.bind(
                mods: mods, key: key,
                pressed: { vm.callRef(pressedRef) },
                released: releasedRef.map { r in { vm.callRef(r) } })
            return 0
        }
        lua_setfield(L, -2, "hotkey")

        // ---- ss.task ----
        vm.beginTable()
        vm.setField("new") { vm in
            let L = vm.L
            guard let path = vm.string(at: 1) else { return 0 }
            var callbackRef: Int32? = nil
            if lua_type(L, 2) == LUA_TFUNCTION {
                lua_pushvalue(L, 2)
                callbackRef = vm.ref()
            }
            var args: [String] = []
            if lua_type(L, 3) == LUA_TTABLE { args = vm.stringArray(at: 3) }

            nextTaskId += 1
            let taskId = nextTaskId
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()
            tasks[taskId] = process
            taskOutputs[taskId] = stdout

            if let cbRef = callbackRef {
                process.terminationHandler = { proc in
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    DispatchQueue.main.async {
                        tasks.removeValue(forKey: taskId)
                        taskOutputs.removeValue(forKey: taskId)
                        vm.callRef(cbRef) { vm in
                            vm.push(Int(proc.terminationStatus))
                            vm.push(output)
                            return 2
                        }
                        vm.unref(cbRef)
                    }
                }
            } else {
                process.terminationHandler = { _ in
                    DispatchQueue.main.async {
                        tasks.removeValue(forKey: taskId)
                        taskOutputs.removeValue(forKey: taskId)
                    }
                }
            }

            // Task object: methods close over taskId.
            vm.beginTable()
            vm.setField("start") { _ in
                if let p = tasks[taskId] { try? p.run() }
                return 0
            }
            vm.setField("interrupt") { _ in
                tasks[taskId]?.interrupt()
                return 0
            }
            vm.setField("terminate") { _ in
                tasks[taskId]?.terminate()
                return 0
            }
            vm.setField("isRunning") { vm in
                vm.push(tasks[taskId]?.isRunning ?? false)
                return 1
            }
            return 1
        }
        lua_setfield(L, -2, "task")

        // ---- ss.alert ----
        vm.beginTable()
        vm.setField("show") { vm in
            let msg = vm.string(at: 1) ?? "?"
            let duration = vm.number(at: 2) ?? 2.0
            vm.push(Alert.show(msg, duration: duration))
            return 1
        }
        vm.setField("closeSpecific") { vm in
            if let id = vm.number(at: 1) { Alert.close(Int(id)) }
            return 0
        }
        lua_setfield(L, -2, "alert")

        // ---- ss.timer ----
        vm.beginTable()
        vm.setField("doAfter") { vm in
            guard let seconds = vm.number(at: 1), lua_type(vm.L, 2) == LUA_TFUNCTION else { return 0 }
            lua_pushvalue(vm.L, 2)
            let fnRef = vm.ref()
            Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                vm.callRef(fnRef)
                vm.unref(fnRef)
            }
            return 0
        }
        vm.setField("doEvery") { vm in
            guard let seconds = vm.number(at: 1), lua_type(vm.L, 2) == LUA_TFUNCTION else { return 0 }
            lua_pushvalue(vm.L, 2)
            let fnRef = vm.ref()
            nextTimerId += 1
            let timerId = nextTimerId
            timers[timerId] = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in
                vm.callRef(fnRef)
            }
            vm.beginTable()
            vm.setField("stop") { vm in
                timers[timerId]?.invalidate()
                timers.removeValue(forKey: timerId)
                vm.unref(fnRef)
                return 0
            }
            return 1
        }
        vm.setField("secondsSinceEpoch") { vm in
            vm.push(Date().timeIntervalSince1970)
            return 1
        }
        vm.setField("waitUntil") { vm in
            guard lua_type(vm.L, 1) == LUA_TFUNCTION, lua_type(vm.L, 2) == LUA_TFUNCTION else { return 0 }
            lua_pushvalue(vm.L, 1)
            let predRef = vm.ref()
            lua_pushvalue(vm.L, 2)
            let actionRef = vm.ref()
            let interval = vm.number(at: 3) ?? 0.1
            nextTimerId += 1
            let timerId = nextTimerId
            timers[timerId] = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                // call predicate, read boolean result
                vm.pushRef(predRef)
                var done = false
                if lua_pcallk(vm.L, 0, 1, 0, 0, nil) == LUA_OK {
                    done = lua_toboolean(vm.L, -1) != 0
                    lua_settop(vm.L, -2)
                }
                if done {
                    timers[timerId]?.invalidate()
                    timers.removeValue(forKey: timerId)
                    vm.callRef(actionRef)
                    vm.unref(predRef)
                    vm.unref(actionRef)
                }
            }
            return 0
        }
        lua_setfield(L, -2, "timer")

        // ---- ss.application ----
        vm.beginTable()
        vm.setField("launchOrFocus") { vm in
            guard let name = vm.string(at: 1) else { return 0 }
            let ws = NSWorkspace.shared
            if let app = ws.runningApplications.first(where: {
                $0.localizedName?.lowercased() == name.lowercased()
            }) {
                app.activate()
                vm.push(true)
            } else {
                if let url = ws.urlForApplication(withBundleIdentifier: name) ??
                    URL(fileURLWithPath: "/Applications/\(name).app") as URL?,
                   FileManager.default.fileExists(atPath: url.path) {
                    ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    vm.push(true)
                } else {
                    vm.push(false)
                }
            }
            return 1
        }
        lua_setfield(L, -2, "application")

        // ---- ss.audiodevice ----
        vm.beginTable()
        vm.setField("inputDeviceNames") { vm in
            let names = AudioDevices.inputDeviceNames()
            lua_createtable(vm.L, Int32(names.count), 0)
            for (i, name) in names.enumerated() {
                vm.push(name)
                lua_rawseti(vm.L, -2, lua_Integer(i + 1))
            }
            return 1
        }
        // Returns the mic chosen in the menubar (if set and currently
        // connected), else nil - config rules decide the fallback.
        vm.setField("selectedInput") { vm in
            if let chosen = UserDefaults.standard.string(forKey: "micDevice"),
               AudioDevices.inputDeviceNames().contains(chosen) {
                vm.push(chosen)
            } else {
                vm.pushNil()
            }
            return 1
        }
        lua_setfield(L, -2, "audiodevice")

        // ---- ss.settings (UserDefaults-backed key/value store) ----
        vm.beginTable()
        vm.setField("get") { vm in
            guard let key = vm.string(at: 1),
                  let value = UserDefaults.standard.string(forKey: "lua." + key) else {
                vm.pushNil()
                return 1
            }
            vm.push(value)
            return 1
        }
        vm.setField("set") { vm in
            guard let key = vm.string(at: 1) else { return 0 }
            if let value = vm.string(at: 2) {
                UserDefaults.standard.set(value, forKey: "lua." + key)
            } else {
                UserDefaults.standard.removeObject(forKey: "lua." + key)
            }
            return 0
        }
        lua_setfield(L, -2, "settings")

        // ---- ss.json ----
        vm.beginTable()
        vm.setField("decode") { vm in
            guard let str = vm.string(at: 1),
                  let data = str.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else {
                vm.pushNil()
                return 1
            }
            vm.pushJSON(obj)
            return 1
        }
        lua_setfield(L, -2, "json")

        // ---- ss.fs ----
        vm.beginTable()
        vm.setField("glob") { vm in
            // ss.fs.glob(dir, luaPattern) -> array of matching paths, newest first
            guard let dir = vm.string(at: 1), let pattern = vm.string(at: 2) else {
                lua_createtable(vm.L, 0, 0)
                return 1
            }
            let fm = FileManager.default
            let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            var matched: [(String, Date)] = []
            for entry in entries where entry.range(of: pattern, options: .regularExpression) != nil {
                let full = (dir as NSString).appendingPathComponent(entry)
                let date = ((try? fm.attributesOfItem(atPath: full)[.creationDate]) as? Date) ?? Date.distantPast
                matched.append((full, date))
            }
            matched.sort { $0.1 > $1.1 }
            lua_createtable(vm.L, Int32(matched.count), 0)
            for (i, m) in matched.enumerated() {
                vm.push(m.0)
                lua_rawseti(vm.L, -2, lua_Integer(i + 1))
            }
            return 1
        }
        vm.setField("remove") { vm in
            if let path = vm.string(at: 1) { try? FileManager.default.removeItem(atPath: path) }
            return 0
        }
        lua_setfield(L, -2, "fs")

        // ---- ss.notify ----
        vm.beginTable()
        vm.setField("send") { vm in
            Alert.show(vm.string(at: 1) ?? "", duration: 3)
            return 0
        }
        lua_setfield(L, -2, "notify")

        // ---- ss.profile ----
        vm.beginTable()
        vm.setField("add") { vm in
            if let name = vm.string(at: 1) { appDelegate?.addProfile(name) }
            return 0
        }
        vm.setField("current") { vm in
            vm.push(appDelegate?.activeProfile ?? "default")
            return 1
        }
        vm.setField("set") { vm in
            if let name = vm.string(at: 1) { appDelegate?.switchProfile(to: name) }
            return 0
        }
        vm.setField("onChange") { vm in
            guard lua_type(vm.L, 1) == LUA_TFUNCTION else { return 0 }
            lua_pushvalue(vm.L, 1)
            let fnRef = vm.ref()
            appDelegate?.profileChangeHandlers.append { name in
                vm.callRef(fnRef) { vm in
                    vm.push(name)
                    return 1
                }
            }
            return 0
        }
        lua_setfield(L, -2, "profile")

        // ---- ss.menubar ----
        vm.beginTable()
        vm.setField("item") { vm in
            guard let title = vm.string(at: 1), lua_type(vm.L, 2) == LUA_TFUNCTION else { return 0 }
            lua_pushvalue(vm.L, 2)
            let fnRef = vm.ref()
            guard let item = appDelegate?.addLuaMenuItem(title: title, handler: { vm.callRef(fnRef) }) else { return 0 }
            vm.beginTable()
            vm.setField("setTitle") { vm in
                if let t = vm.string(at: 1) ?? vm.string(at: 2) { item.title = t }
                return 0
            }
            vm.setField("setChecked") { vm in
                let on = lua_toboolean(vm.L, 1) != 0 || lua_toboolean(vm.L, 2) != 0
                item.state = on ? .on : .off
                return 0
            }
            return 1
        }
        vm.setField("setTitle") { vm in
            if let t = vm.string(at: 1) { appDelegate?.setStatusTitle(t) }
            return 0
        }
        lua_setfield(L, -2, "menubar")

        vm.setGlobalTable("ss")

        // Alias for familiarity / partial Hammerspoon compatibility.
        lua_getglobal(L, "ss")
        vm.setGlobalTable("hs")
    }
}
