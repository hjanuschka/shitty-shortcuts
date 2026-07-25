import CLua
import Foundation

// Minimal Lua <-> Swift bridge: enough to host the config script and
// call back and forth. Not general purpose, deliberately small.
final class LuaVM {
    let L: OpaquePointer

    private final class FnBox {
        let fn: (LuaVM) -> Int32
        init(_ fn: @escaping (LuaVM) -> Int32) { self.fn = fn }
    }

    private var boxes: [FnBox] = []
    private static var vms: [OpaquePointer: LuaVM] = [:]

    init() {
        L = luaL_newstate()
        luaL_openlibs(L)
        LuaVM.vms[L] = self
    }

    static func vm(for state: OpaquePointer) -> LuaVM {
        // Callbacks always run on the main state in this app.
        if let vm = vms[state] { return vm }
        // Coroutine states share the registry; fall back to any VM (we only have one).
        return vms.values.first!
    }

    // Push a Swift closure as a Lua C function.
    func pushFunction(_ fn: @escaping (LuaVM) -> Int32) {
        let box = FnBox(fn)
        boxes.append(box)
        lua_pushlightuserdata(L, Unmanaged.passUnretained(box).toOpaque())
        lua_pushcclosure(L, { rawState in
            guard let rawState else { return 0 }
            let boxPtr = lua_touserdata(rawState, clua_upvalueindex(1))!
            let box = Unmanaged<FnBox>.fromOpaque(boxPtr).takeUnretainedValue()
            return box.fn(LuaVM.vm(for: rawState))
        }, 1)
    }

    // Store the Lua value on top of the stack in the registry, return a ref.
    func ref() -> Int32 { luaL_ref(L, clua_registryindex()) }
    func unref(_ r: Int32) { luaL_unref(L, clua_registryindex(), r) }
    func pushRef(_ r: Int32) { lua_rawgeti(L, clua_registryindex(), lua_Integer(r)) }

    // Call a registry-ref'd function with pre-pushed args.
    func callRef(_ r: Int32, argPusher: (LuaVM) -> Int32 = { _ in 0 }) {
        pushRef(r)
        let nargs = argPusher(self)
        if lua_pcallk(L, nargs, 0, 0, 0, nil) != LUA_OK {
            let err = string(at: -1) ?? "unknown error"
            lua_settop(L, -2)
            NSLog("shitty-shortcuts: lua callback error: %@", err)
            Alert.show("lua error: \(err)", duration: 4)
        }
    }

    @discardableResult
    func doFile(_ path: String) -> Bool {
        if luaL_loadfilex(L, path, nil) != LUA_OK || lua_pcallk(L, 0, LUA_MULTRET, 0, 0, nil) != LUA_OK {
            let err = string(at: -1) ?? "unknown error"
            lua_settop(L, -2)
            NSLog("shitty-shortcuts: config error: %@", err)
            Alert.show("config error: \(err)", duration: 6)
            return false
        }
        return true
    }

    // -- stack helpers ------------------------------------------------------

    func string(at idx: Int32) -> String? {
        guard lua_type(L, idx) == LUA_TSTRING else { return nil }
        var len = 0
        guard let cstr = lua_tolstring(L, idx, &len) else { return nil }
        return String(decoding: UnsafeRawBufferPointer(start: cstr, count: len), as: UTF8.self)
    }

    func number(at idx: Int32) -> Double? {
        var isnum: Int32 = 0
        let n = lua_tonumberx(L, idx, &isnum)
        return isnum != 0 ? n : nil
    }

    func push(_ s: String) { lua_pushstring(L, s) }
    func push(_ d: Double) { lua_pushnumber(L, d) }
    func push(_ i: Int) { lua_pushinteger(L, lua_Integer(i)) }
    func push(_ b: Bool) { lua_pushboolean(L, b ? 1 : 0) }
    func pushNil() { lua_pushnil(L) }

    // Push any JSON-decoded object as a Lua value.
    func pushJSON(_ value: Any) {
        switch value {
        case let s as String: push(s)
        case let n as NSNumber:
            // NSNumber(1) as? Bool succeeds, so a plain `as Bool` case would
            // turn JSON integers into booleans. Check the stored type instead.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                push(n.boolValue)
            } else if n.doubleValue == n.doubleValue.rounded(), abs(n.doubleValue) < 1e15 {
                push(Int(n.int64Value))  // integers stay integers ("id:1", not "id:1.0")
            } else {
                push(n.doubleValue)
            }
        case let a as [Any]:
            lua_createtable(L, Int32(a.count), 0)
            for (i, item) in a.enumerated() {
                pushJSON(item)
                lua_rawseti(L, -2, lua_Integer(i + 1))
            }
        case let d as [String: Any]:
            lua_createtable(L, 0, Int32(d.count))
            for (k, v) in d {
                push(k)
                pushJSON(v)
                lua_settable(L, -3)
            }
        default: pushNil()
        }
    }

    // Read a string array from a Lua table at idx.
    func stringArray(at idx: Int32) -> [String] {
        var result: [String] = []
        let n = lua_rawlen(L, idx)
        for i in 1...max(n, 0) {
            lua_rawgeti(L, idx, lua_Integer(i))
            if let s = string(at: -1) { result.append(s) }
            lua_settop(L, -2)
        }
        return result
    }

    // -- table building helpers --------------------------------------------

    func beginTable() { lua_createtable(L, 0, 8) }

    func setField(_ name: String, _ fn: @escaping (LuaVM) -> Int32) {
        pushFunction(fn)
        lua_setfield(L, -2, name)
    }

    func setGlobalTable(_ name: String) { lua_setglobal(L, name) }
}
