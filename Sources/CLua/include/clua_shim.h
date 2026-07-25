// Shims for Lua macros that Swift's clang importer cannot handle.
#ifndef CLUA_SHIM_H
#define CLUA_SHIM_H

#include "lua.h"
#include "lauxlib.h"

static inline int clua_registryindex(void) { return LUA_REGISTRYINDEX; }
static inline int clua_upvalueindex(int i) { return lua_upvalueindex(i); }

#endif
