-- Focus-or-create a Chrome tab: the "one tab per web app" pattern.
--
-- Uses Chrome's `--focus` flag (Chrome 143+, see
-- https://www.januschka.com/chromium-focus-feature.html):
--   * if a tab matches the selector, the most-recently-used one is focused
--     (across ALL Chrome windows)
--   * if nothing matches, the positional URL is opened in a new tab
--   * trailing `*` = URL prefix match, otherwise exact match
--
-- Result: pressing the key never creates duplicate Gmail tabs. Ever.

local hyper = { "cmd", "alt", "ctrl", "shift" }
local chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

ss.hotkey.bind(hyper, "g", function()
  ss.task.new(chrome, nil, {
    "--focus=https://mail.google.com/*",
    "https://mail.google.com",
  }):start()
end)
