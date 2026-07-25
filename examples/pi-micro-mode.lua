-- "Micro mode": turn a $17 macro keypad into a control surface for the
-- pi coding agent (https://pi.dev) running remotely inside zellij.
--
-- Workflow: ssh -> zellij session -> pi in the focused pane.
-- Keys are injected with `zellij action write` (raw bytes), so it works
-- from anywhere - no window focus needed on the remote side.
--
-- Keypad setup: program a second hardware layer with different hyper
-- chords (see ch57x-keypad.yaml), flip the side switch to enter micro mode.
--
--   btn 1: interrupt      btn 2: submit
--   btn 3: model picker   btn 4: hold-to-talk (whisper -> pi editor)
--   btn 5: thinking level btn 6: expand tools
--   knob:  rotate = up/down in selectors, press = confirm

local hyper = { "cmd", "alt", "ctrl", "shift" }
local piHost = "you@your-dev-box.example.com"
local piZellij = "zellij --session main action "

local function piAction(actionArgs, label)
  ss.task.new("/usr/bin/ssh", nil, {
    "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
    piHost, piZellij .. actionArgs,
  }):start()
  if label then ss.alert.show("π " .. label, 0.8) end
end

-- pi default keybindings -> raw bytes (see pi docs/keybindings.md):
--   escape=27  enter=13  ctrl+l=12  ctrl+o=15  shift+tab=27 91 90
--   up=27 91 65  down=27 91 66
ss.hotkey.bind(hyper, "q", function() piAction("write 27", "interrupt") end)
ss.hotkey.bind(hyper, "w", function() piAction("write 13", "submit") end)
ss.hotkey.bind(hyper, "e", function() piAction("write 12", "models") end)
ss.hotkey.bind(hyper, "t", function() piAction("write 27 91 90", "thinking") end)
ss.hotkey.bind(hyper, "y", function() piAction("write 15", "tools") end)
ss.hotkey.bind(hyper, "7", function() piAction("write 27 91 65") end)
ss.hotkey.bind(hyper, "8", function() piAction("write 27 91 66") end)
ss.hotkey.bind(hyper, "0", function() piAction("write 13") end)

-- btn 4: hold-to-talk. Records locally, transcribes with whisper.cpp and
-- TYPES the result into pi's editor (review it, then btn 2 to submit).
local soxBin = "/usr/local/bin/sox"
local whisperBin = "/usr/local/bin/whisper-cli"
local whisperModel = os.getenv("HOME") .. "/models/whisper/ggml-small.en.bin"
local recFile = "/tmp/pi-voice.wav"
local recTask = nil

local function startRecording()
  if recTask and recTask.isRunning() then return end
  ss.fs.remove(recFile)
  local mic = ss.audiodevice.selectedInput() or "MacBook Pro Microphone"
  recTask = ss.task.new(soxBin, nil,
    { "-q", "-t", "coreaudio", mic, "-r", "16000", "-c", "1", recFile })
  recTask.start()
  ss.alert.show("🎙 dictating to π...", 1)
end

local function stopAndTranscribe()
  if not (recTask and recTask.isRunning()) then return end
  recTask.interrupt()
  recTask = nil
  ss.timer.doAfter(0.3, function()
    local alertId = ss.alert.show("🧠 transcribing...", 999)
    ss.task.new(whisperBin, function(exitCode, stdOut)
      ss.alert.closeSpecific(alertId)
      if exitCode ~= 0 then ss.alert.show("transcription failed") return end
      local text = stdOut:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n+", " ")
      if text == "" or text:find("%[BLANK_AUDIO%]") then ss.alert.show("heard nothing") return end
      ss.alert.show("π > " .. text, 2)
      local quoted = "'" .. text:gsub("'", "'\\''") .. "'"
      piAction("write-chars " .. quoted)
    end, { "-m", whisperModel, "-f", recFile, "--no-timestamps", "-np" }):start()
  end)
end

ss.hotkey.bind(hyper, "r", startRecording, stopAndTranscribe)
