-- Example shitty-shortcuts config
-- Save as ~/.config/shitty-shortcuts/init.lua
--
-- Buttons on a macro keypad send hyper chords (cmd+ctrl+alt+shift+N),
-- see examples/ch57x-keypad.yaml for the matching keypad mapping.

local hyper = { "cmd", "alt", "ctrl", "shift" }
local kittenBin = "/Applications/kitty.app/Contents/MacOS/kitten"
local chromeBin = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

-- ---------------------------------------------------------------------------
-- kitty helpers (needs `listen_on unix:/tmp/kitty-ctl` in kitty.conf)
-- ---------------------------------------------------------------------------

local function findKittySocket()
  -- kitty appends its PID to the socket path; newest one wins
  return ss.fs.glob("/tmp", "^kitty-ctl-[0-9]+$")[1]
end

local function kitten(args, callback)
  local sock = findKittySocket()
  if not sock then
    ss.alert.show("kitty control socket not found - is kitty running?")
    return
  end
  local full = { "@", "--to", "unix:" .. sock }
  for _, a in ipairs(args) do table.insert(full, a) end
  ss.task.new(kittenBin, callback, full):start()
end

local function focusKitty()
  ss.application.launchOrFocus("kitty")
end

-- find the kitty window whose foreground process matches `pattern`, focus it
local function focusKittyWindowByCmdline(pattern)
  focusKitty()
  kitten({ "ls" }, function(exitCode, stdOut)
    if exitCode ~= 0 then return end
    local data = ss.json.decode(stdOut)
    if not data then return end
    for _, osw in ipairs(data) do
      for _, tab in ipairs(osw.tabs or {}) do
        for _, win in ipairs(tab.windows or {}) do
          for _, proc in ipairs(win.foreground_processes or {}) do
            if table.concat(proc.cmdline or {}, " "):find(pattern, 1, true) then
              kitten({ "focus-window", "-m", "id:" .. win.id })
              return
            end
          end
        end
      end
    end
    ss.alert.show("no kitty window running '" .. pattern .. "'")
  end)
end

-- ---------------------------------------------------------------------------
-- voice input: record -> whisper.cpp -> type into focused kitty window
-- ---------------------------------------------------------------------------

local soxBin = "/usr/local/bin/sox"
local whisperBin = "/usr/local/bin/whisper-cli"
local whisperModel = os.getenv("HOME") .. "/models/whisper/ggml-small.en.bin"
local recTask = nil
local recFile = "/tmp/shitty-voice.wav"

-- mic preference rules (lua patterns, first match wins).
-- A device picked in menubar > Microphone always takes priority.
local micRules = { "sony", "wf%-1000", "airpods", "headset" }
local micFallback = "MacBook Pro Microphone" -- list yours: ss.audiodevice.inputDeviceNames()

local function pickMic()
  -- 1. explicit menubar selection (only if currently connected)
  local selected = ss.audiodevice.selectedInput()
  if selected then return selected end
  -- 2. preference rules
  for _, name in ipairs(ss.audiodevice.inputDeviceNames()) do
    for _, rule in ipairs(micRules) do
      if name:lower():find(rule) then return name end
    end
  end
  -- 3. fallback
  return micFallback
end

local function transcribeAndSend()
  local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local startedAt = ss.timer.secondsSinceEpoch()
  local frame = 0
  local alertId = ss.alert.show("🧠 transcribing...", 999)
  local spinner = ss.timer.doEvery(0.15, function()
    frame = frame + 1
    local elapsed = string.format("%.1fs", ss.timer.secondsSinceEpoch() - startedAt)
    ss.alert.closeSpecific(alertId)
    alertId = ss.alert.show(frames[(frame % #frames) + 1] .. " transcribing... " .. elapsed, 999)
  end)

  local function finish(message, duration)
    spinner.stop()
    ss.alert.closeSpecific(alertId)
    if message then ss.alert.show(message, duration or 2) end
  end

  ss.task.new(whisperBin, function(exitCode, stdOut)
    if exitCode ~= 0 then
      finish("transcription failed")
      return
    end
    local text = stdOut:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n+", " ")
    if text == "" or text:find("%[BLANK_AUDIO%]") then
      finish("heard nothing")
      return
    end
    finish("> " .. text, 2)
    kitten({ "send-text", "-m", "state:focused", "--", text })
  end, { "-m", whisperModel, "-f", recFile, "--no-timestamps", "-np" }):start()
end

local function startRecording()
  if recTask and recTask.isRunning() then return end
  ss.fs.remove(recFile)
  local mic = pickMic()
  recTask = ss.task.new(soxBin, nil,
    { "-q", "-t", "coreaudio", mic, "-r", "16000", "-c", "1", recFile })
  recTask.start()
  ss.alert.show("🎙 " .. mic, 1)
end

local function stopAndTranscribe()
  if not (recTask and recTask.isRunning()) then return end
  recTask.interrupt()
  recTask = nil
  ss.timer.doAfter(0.3, transcribeAndSend)
end

-- ---------------------------------------------------------------------------
-- bindings
-- ---------------------------------------------------------------------------

-- buttons 1-3: kitty tabs 1-3
for i = 1, 3 do
  ss.hotkey.bind(hyper, tostring(i), function()
    focusKitty()
    kitten({ "focus-tab", "-m", "index:" .. (i - 1) })
  end)
end

-- button 4: push-to-talk voice input (hold to record, release to transcribe)
ss.hotkey.bind(hyper, "4", startRecording, stopAndTranscribe)

-- button 5: focus (or create) your favorite web app tab in Chrome
ss.hotkey.bind(hyper, "5", function()
  ss.task.new(chromeBin, nil,
    { "--focus=https://github.com/*", "https://github.com" }):start()
end)

-- button 6: jump to the kitty window running a specific process
ss.hotkey.bind(hyper, "6", function()
  focusKittyWindowByCmdline("ssh")
end)

-- knob press: voice input toggle (for knobs that can't hold)
ss.hotkey.bind(hyper, "9", function()
  if recTask and recTask.isRunning() then stopAndTranscribe() else startRecording() end
end)
