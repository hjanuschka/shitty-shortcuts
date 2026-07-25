-- Profiles: same buttons, different meanings - switch from the menubar.
-- The active profile is persisted across restarts, and long-press works
-- great as a hardware toggle if your keypad has no layer switch.

local hyper = { "cmd", "alt", "ctrl", "shift" }

ss.profile.add("desktop")
ss.profile.add("pi.dev")

-- update the menubar icon per profile
ss.profile.onChange(function(name)
  ss.menubar.setTitle(name == "pi.dev" and "π⌨️" or "💩⌨️")
end)

-- dispatch a button per profile
ss.hotkey.bind(hyper, "1", function()
  if ss.profile.current() == "pi.dev" then
    ss.alert.show("interrupt pi")
  else
    ss.alert.show("kitty tab 1")
  end
end)

-- long-press a button (>= 0.5s) to toggle profiles without the menubar
local downAt = nil
ss.hotkey.bind(hyper, "6", function()
  downAt = ss.timer.secondsSinceEpoch()
end, function()
  if ss.timer.secondsSinceEpoch() - (downAt or 0) >= 0.5 then
    ss.profile.set(ss.profile.current() == "pi.dev" and "desktop" or "pi.dev")
  else
    ss.alert.show("short press action")
  end
end)

-- you can also add arbitrary menubar entries:
ss.menubar.item("Say hello", function()
  ss.alert.show("hello from lua 👋")
end)
