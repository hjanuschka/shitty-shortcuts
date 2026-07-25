-- Web-app hotkeys: jump to the Chrome tab if it exists, create it if not.
-- Uses the `chrome --focus` feature (Chrome 143+):
--   trailing `*`  = URL prefix match
--   positional URL = opened when nothing matches

local hyper = { "cmd", "alt", "ctrl", "shift" }
local chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

local function webapp(selector, url)
  return function()
    ss.task.new(chrome, nil, { "--focus=" .. selector, url }):start()
  end
end

ss.hotkey.bind(hyper, "g", webapp("https://mail.google.com/*", "https://mail.google.com"))
ss.hotkey.bind(hyper, "c", webapp("https://calendar.google.com/*", "https://calendar.google.com"))
ss.hotkey.bind(hyper, "h", webapp("https://github.com/*", "https://github.com"))
ss.hotkey.bind(hyper, "y", webapp("https://news.ycombinator.com/*", "https://news.ycombinator.com"))
ss.hotkey.bind(hyper, "m", webapp("https://music.youtube.com/*", "https://music.youtube.com"))
