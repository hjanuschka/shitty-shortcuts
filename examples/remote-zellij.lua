-- Drive a zellij session on a remote box: keypad buttons select zellij tabs
-- inside your ssh session. Requires passwordless ssh (BatchMode).

local hyper = { "cmd", "alt", "ctrl", "shift" }
local remoteHost = "you@your-dev-box.example.com"

local function zellijTab(n)
  ss.task.new("/usr/bin/ssh", nil, {
    "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
    remoteHost,
    "~/.cargo/bin/zellij --session main action go-to-tab " .. n,
  }):start()
end

for i = 1, 3 do
  ss.hotkey.bind(hyper, tostring(i), function() zellijTab(i) end)
end

-- bonus: same idea works for remote tmux:
--   tmux select-window -t :N
