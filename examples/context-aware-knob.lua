-- Context-aware knob: one physical control, different meaning per app.
--
--   Chrome frontmost -> cycle Chrome tabs (wraps around)
--   kitty frontmost  -> cycle kitty tabs
--                       (or remote zellij tabs when an ssh session is focused)
--   anything else    -> system volume
--
-- The knob sends hyper+7 (ccw) / hyper+8 (cw), see ch57x-keypad.yaml.

local hyper = { "cmd", "alt", "ctrl", "shift" }
local kittenBin = "/Applications/kitty.app/Contents/MacOS/kitten"

local function findKittySocket()
  return ss.fs.glob("/tmp", "^kitty-ctl-[0-9]+$")[1]
end

local function kitten(args, callback)
  local sock = findKittySocket()
  if not sock then return end
  local full = { "@", "--to", "unix:" .. sock }
  for _, a in ipairs(args) do table.insert(full, a) end
  ss.task.new(kittenBin, callback, full):start()
end

-- Chrome: rotate through tabs with wraparound (AppleScript, needs the
-- one-time Automation permission prompt)
local function chromeCycleTab(direction)
  local script
  if direction > 0 then
    script = 'tell application "Google Chrome" to tell front window\n' ..
             'set active tab index to ((active tab index) mod (count of tabs)) + 1\n' ..
             'end tell'
  else
    script = 'tell application "Google Chrome" to tell front window\n' ..
             'set active tab index to (((active tab index) + (count of tabs) - 2) mod (count of tabs)) + 1\n' ..
             'end tell'
  end
  ss.task.new("/usr/bin/osascript", nil, { "-e", script }):start()
end

-- is the focused kitty window an ssh session?
local function focusedKittyIsSSH(data)
  for _, osw in ipairs(data or {}) do
    for _, tab in ipairs(osw.tabs or {}) do
      for _, win in ipairs(tab.windows or {}) do
        if win.is_focused then
          for _, proc in ipairs(win.foreground_processes or {}) do
            if table.concat(proc.cmdline or {}, " "):find("ssh ", 1, true) then
              return true
            end
          end
        end
      end
    end
  end
  return false
end

local function volumeDelta(delta)
  ss.task.new("/usr/bin/osascript", nil, {
    "-e", "set volume output volume ((output volume of (get volume settings)) + " .. delta .. ")",
  }):start()
end

local function knobTurn(direction)
  local front = ss.application.frontmost()
  if front == "Google Chrome" then
    chromeCycleTab(direction)
  elseif front == "kitty" then
    kitten({ "ls" }, function(exitCode, stdOut)
      local data = exitCode == 0 and ss.json.decode(stdOut) or nil
      if data and focusedKittyIsSSH(data) then
        -- drive the remote multiplexer instead of local tabs
        ss.task.new("/usr/bin/ssh", nil, {
          "-o", "BatchMode=yes", "you@your-dev-box.example.com",
          "zellij --session main action " ..
            (direction > 0 and "go-to-next-tab" or "go-to-previous-tab"),
        }):start()
      else
        kitten({ "action", direction > 0 and "next_tab" or "previous_tab" })
      end
    end)
  else
    volumeDelta(direction > 0 and 6 or -6)
  end
end

ss.hotkey.bind(hyper, "7", function() knobTurn(-1) end)
ss.hotkey.bind(hyper, "8", function() knobTurn(1) end)

-- The same pattern works for buttons: one "submit" key for every app.
ss.hotkey.bind(hyper, "2", function()
  local front = ss.application.frontmost()
  if front == "kitty" then
    kitten({ "send-key", "-m", "state:focused", "enter" })
  else
    ss.alert.show("submit in " .. front .. "? map it here!")
  end
end)
