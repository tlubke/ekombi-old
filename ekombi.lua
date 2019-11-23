-- Ekombi
-- @tyler
--  polyrhythmic sampler
--
--
-- 4, two-track channels
-- ------------------------------------------
-- trackA: sets the length
-- of the tuplet
--
-- trackB: sets length of the
-- 'measure' in quarter notes
-- -------------------------------------------
--
-- works with or without grid
--
-- grid controls
-- ---------------------------------
-- hold a key and press another
-- key in the same row to set
-- the length of the track
--
-- tapping gridkeys toggles the
-- tuplet subdivisions and
-- quarter notes on/off
-- -------------------------------------------
--
-- norns controls
-- ------------------------------------------
-- PLAY MODE
-- enc1: bpm
-- enc2: select preset
-- enc3: filter cutoff
--
-- key1: save preset
-- key2: load preset
-- key3: stop clock
-- key3: HOLD->EDIT MODE
--
-- EDIT MODE
-- enc1: track select
-- enc2: subdiv. select
-- enc3: length select
--
-- key2: discard changes
-- key3: toggle subdiv. on/off
-- key3: HOLD->apply changes
-- ---------------------------------------------



engine.name = 'Ack'

local ack = require 'ack/lib/ack'

local g = grid.connect()



------------
-- variables
------------
local mode = "play"

-- clocking variables
local position = 0
local q_position = 0
local counter = nil
local ppq = 480
local running = false

-- midi variables
midi_out_device = {1, 1, 1, 1}
midi_out_channel = {1, 1, 1, 1}
midi_out_note = {64, 64, 64, 64}
midi_notes_on = {{},{},{},{}}

-- preset variables
local preset_select = 1

-- grid variables
-- for holding one gridkey and pressing another further right
local g_held = {}
local g_heldMax = {}
local done = {}
local first = {}
local second = {}
for row = 1,8 do
  g_held[row] = 0
  g_heldMax[row] = 0
  done[row] = 0
  first[row] = 0
  second[row] = 0
end

-- encoder variables
-- for editing/controling without grid
-- 1-indexed similar for grid and track[]
local row_select = 1
local sub_select = 1
local length_select = 1
local cursor = {row_select, length_select, sub_select}

-- 4, two-track channels (A is even rows, TrackB is odd rows)
local track = {}
-- for seeing stored presets
local preview = {}
-- build up changes to be pushed to track[]
local buffer = {}
-- if channel n is in mute[], it will not be triggered
-- mute is applied to even-numbered rows to avoid additional
-- arithmetic in tick(). Counting errors would result from
-- having .mute inside track[]
local mute = {[2] = 0, [4] = 0, [6] = 0, [8] = 0}

-- initialize track[]
for i=1,8 do
  if i % 2 == 1 then
    track[i] = {}
    track[i][1] = {}
    track[i][1][1] = 0
  else
    track[i] = {}
    for n=1, 16 do
      track[i][n] = {}
      for j=1, 16 do
        track[i][n][j] = 1
      end
    end
  end
end



----------------
-- initilization
----------------
function init()

  -- parameters
  params:add_number("bpm", "bpm", 15, 400, 60)
  ack.add_effects_params()

  params:add_separator()

  for channel=1,4 do
    params:add{type = "number", id = channel.. "_midi_out_device", name = channel .. ": MIDI device",
      min = 1, max = 4, default = 1,
      action = function(value) midi_out_device[channel] = value connect_midi() end}
    params:add{type = "number", id = channel.. "_midi_out_channel", name = channel ..": MIDI channel",
      min = 1, max = 16, default = 1,
      action = function(value)
        -- all_notes_off()
        midi_out_channel[channel] = value end}
    params:add{type = "number", id = channel.. "_midi_note", name = channel .. ": MIDI note",
      min = 0, max = 127, default = 64,
      action = function(value)
        midi_out_note[channel] = value end}
    params:add{type = "option", id = channel.. "_random", name = channel..": random sample",
        options = {"off", "on"}}
    ack.add_channel_params(channel)

    if channel ~= 4 then
      params:add_separator()
    end

  end

  params:read("ekombi.pset")

  -- metronome setup
  clk = metro.init()
  clk.time = 60 / (params:get("bpm") * ppq)
  clk.count = -1
  clk.event = tick

  -- counter:start()
  blink = 0
  blinker = metro.init()
  blinker.time = 1/11
  blinker.count = -1
  blinker.event = function(b)
    blink = blink + 1
    redraw()
  end

  -- displays saved presets for peek.time seconds
  peek = metro.init()
  peek.time = 2
  peek.count = 1
  peek.event = function(x)
    preview = {}
    redraw_grid()
    redraw()
  end

  connect_midi()
  load_preset()
  redraw_grid()
  redraw()
end

function connect_midi()
  for channel=1, 4 do
    midi_out_device[channel] = midi.connect(params:get(channel.. "_midi_out_device"))
  end
end

local function all_notes_off(channel)
  for i = 1, tab.count(midi_notes_on[channel]) do
    midi_out_device[channel]:note_off(midi_notes_on[i])
  end
  midi_notes_on[channel] = {}
end



-------------------------
-- grid control functions
-------------------------
function g.key(x, y, z)
  -- don't enter edit mode if mute-button is hit
  if mode == "play" and not (x == 16 and y % 2 == 1) then
    mode = "edit"
    buffer = deepcopy(track)
    blinker:start()
  end

  -- sends data to two separate functions
  gridkeyhold(x,y,z)
  gridkey(x,y,z)
  -- print(x,y,z)
end

function gridkey(x,y,z)
  local count = 0

  if z == 1 then
    -- mute track
    if mode == "play" and (x == 16 and y % 2 == 1) then
      mute[y+1] = ~mute[y+1]
      return
    end

    count = tab.count(buffer[y])

    -- error control
    if count == 0 or count == nil then
      if x > 1 then
        return
      elseif x == 1 then
        buffer[y] = {}
        buffer[y][x] = {}
        buffer[y][x][x] = 1
        redraw_grid()
        redraw()
      end
      return

    else
      -- note toggle on/off
      if x > count then
        return
      else
        if buffer[y][count][x] == 1 then
          buffer[y][count][x] = 0
        else
          buffer[y][count][x] = 1
        end
        update_cursor("row", y - row_select)
        update_cursor("column", x - sub_select)
      end

    end
  end

  redraw()
  redraw_grid()
end

function gridkeyhold(x, y, z)
  -- odd numbered tracks should only go to 15
  if x == 16 and y % 2 == 1 then
    return
  end

  if z == 1 and g_held[y] then g_heldMax[y] = 0 end
  g_held[y] = g_held[y] + (z*2 -1)

  if g_held[y] > g_heldMax[y] then g_heldMax[y] = g_held[y] end

  if y > 8 and g_held[y] == 1 then
    first[y] = x
  elseif y <= 8 and g_held[y] == 2 then
    second[y] = x
  elseif z == 0 then
    if y <= 8 and g_held[y] == 1 and g_heldMax[y] == 2 then
      buffer[y] = {}
      for i = 1, second[y] do
        buffer[y][i] = {}
        for n=1, i do
          buffer[y][i][n] = 1
        end
      end
      update_cursor("column", second[y] - sub_select)
    end
  end

  redraw()
  redraw_grid()
end



---------------------------
-- norns control functions
---------------------------
function enc(n,d)
  if n == 1 then
    if mode == "play" then
      params:delta("bpm",d)
    elseif mode == "edit" then
      update_cursor("row", d)
    end
  end

  if n == 2 then
    if mode == "play" then
      preset_select = util.clamp(preset_select + d, 1, 16)
      preview_preset()
      peek:start()
      -- print("preset:"..preset_select)
    elseif mode == "edit" then
      update_cursor("column", d)
    end
  end

  if n == 3 then
    if mode == "play" then
      for i=1, 4 do
        params:delta(i.."_filter_cutoff", d)
      end
    elseif mode == "edit" then
      update_cursor("length", d)
    end
  end

  redraw_grid()
  redraw()
end

function key(n,z)

  if z == 1 then

    -- key-1 only functions when held
    if n == 1 then
      if mode == "play" then
        save_preset()
      end
    end

    if n == 2 or n == 3 then
      key_held = util.time()
    end

  else

    if n == 2 then
      if key_held - util.time() < -0.333 then -- hold for a third of a second
        if mode == "play" then
          load_preset()
          preset_current = preset_select
        end
      else
        discard_changes()
        mode = "play"
        blinker:stop()
      end
    end

    if n == 3 then
      if key_held - util.time() < -0.333 then -- hold for a third of a second
        if mode == "play" then
          buffer = deepcopy(track)
          mode = "edit"
          blinker:start()
        else
          apply_changes()
          mode = "play"
          blinker:stop()
        end
        -- print("mode "..mode)
      else
        if mode == "play" then
          if running then
            stop_clock()
          else
            reset_clock()
          end
        elseif mode == "edit" then
          buffer[row_select][length_select][sub_select] = (buffer[row_select][length_select][sub_select] + 1) % 2
        end
      end
    end
  end

  redraw_grid()
  redraw()
end



------------------
-- active functions
-------------------
--[[
    this is the heart of polyrhythm generating, each track is checked to see which note divisions are on or off,
    first, the B track is checked (the 'quarter' note, before the tuplet division) then if the note is on, we check
    each of the subdivisions, and if those turn out to be on, the nth subdivision of the tuple of the track is triggered.
    The complicated divisons and multiplations of each of the track sets and subsets is to find the exact position value,
    that when / by that value returns n-1, the track triggers.
]]--
function tick()
  local count = 0
  local pending = {}

  clk.time = 60 / (params:get("bpm") * ppq)

  position = (position + 1) % (ppq)

  if position == 0 then
    q_position = q_position + 1
    fast_redraw_grid()
  end

  for i=2, 8, 2 do
    count = tab.count(track[i])
    if count == 0 or count == nil then
      return
    else
      if mute[i] == 0 and track[i][count][(q_position % count)+1] == 1then
        table.insert(pending,i-1)
      end
    end
  end

  if tab.count(pending) > 0 then
    for i=1, tab.count(pending) do
      count = tab.count(track[pending[i]])
      if count == 0 or count == nil then
        return
      else
        for n=1, count do
          if position / ( ppq // (tab.count(track[pending[i]][count]))) == n-1 then
            if track[pending[i]][count][n] == 1 then
              t = (pending[i]//2) + 1
              engine.trig(t - 1) -- samples are 0-3
              all_notes_off(t)
              if params:get(t.."_random") == 2 then
                -- 1 == "off", 2 == "on"
                load_random(t)
              end
              -- print(t - 1)
              midi_out_device[t]:note_on(midi_out_note[t], 96, midi_out_channel[t]) -- midi trig
              table.insert(midi_notes_on[t], {midi_out_note[t], 96, midi_out_channel[t]})
            end
          end
        end
      end
    end
  end

end



---------------------------
-- refresh/redraw functions
---------------------------
function redraw()
  local display = {}

  screen.clear()
  screen.aa(0)
  screen.font_face(1)

  -- decide which pattern to display
  if tab.count(preview) > 0 then
    screen.level(8)
    -- previously saved patterns
    display = preview
  else
    screen.level(15)
    if mode == "play" then
      -- the currently playing pattern
      display = track
    elseif mode == "edit" then
      -- the currently editing pattern
      display = buffer
    end
  end

  for i=1, 8 do
    for n=1, tab.count(display[i]) do
      if display[i][tab.count(display[i])][n] == 1 then
        if mode == "edit" and cursor[1] == i and cursor[3] == n and blink % 3 == 0 then
          -- pass
        else
          screen.rect((n-1)*7, 1 + i*7, 6, 6)
        end
        screen.fill()
        screen.move(tab.count(display[i])*7, i*7 + 7)
        screen.text(tab.count(display[i]))
      else
        if mode == "edit" and cursor[1] == i and cursor[3] == n and blink % 3 == 0 then
          -- pass
        else
          screen.rect(1 + (n-1)*7, 2 + i*7, 5, 5)
        end
        screen.stroke()
        screen.move(tab.count(display[i])*7, 7 + i*7)
        screen.text(tab.count(display[i]))
      end
    end
  end

  -- bpm display
  screen.level(15)
  screen.move(0,5)
  screen.text("bpm:"..params:get("bpm"))

  -- mute buttons
  for i=2, 8, 2 do
    if mute[i] ~= 0 then
      screen.move(123, 7 + (i - 1) * 7)
      screen.text("M")
    end
  end

  -- pause/play icon
  if not running then
    screen.rect(123,57,2,6)
    screen.rect(126,57,2,6)
    screen.fill()
  else
    screen.move(123,57)
    screen.line_rel(6,3)
    screen.line_rel(-6,3)
    screen.fill()
  end

  -- selected preset
  if tab.count(preview) == 0 then
    screen.level(8)
  end
  screen.move(91,5)
  screen.text("preset:")
  screen.move_rel(0,1)
  screen.font_face(2)
  screen.text(string.format("%02d", preset_select))


  screen.update()
end

function redraw_grid()
  local count = 0
  local display = {}
  local offset = 1

  g:all(0)

  -- decide which pattern to display
  if tab.count(preview) > 0 then
    offset = 2
    display = preview
  else
    if mode == "play" then
      -- the currently playing pattern
      display = track
    elseif mode == "edit" then
      -- the currently editing pattern
      display = buffer
    end
  end

  -- draw channels with sub divisions on/off
  for i=1, 8 do
    for n=1, tab.count(display[i]) do
      count = tab.count(display[i])
      if count == 0 or count == nil then return
      else
        if i % 2 == 1 then
          if display[i][count][n] == 1 then
            g:led(n, i, 12 / offset)
          else
            g:led(n, i, 4 / offset)
          end

        elseif i % 2 == 0 then
          if display[i][count][n] == 1 then
            g:led(n, i, 8 / offset)
          else
            g:led(n, i, 2 / offset)
          end
          g:led((q_position % count) + 1, i, 15)
        end
      end
    end
  end

  -- draw mute buttons
  for i=2, 8, 2 do
    if mute[i] == 0 then
      g:led(16, i-1, 4)
    else
      g:led(16, i-1, 15)
    end
  end

  g:refresh()
end

function fast_redraw_grid()
  local count = 0
  local display = {}

  if mode == "play" then
    display = track
  elseif mode == "edit" then
    display = buffer
  end

  for i=1, 8 do
    for n=1, tab.count(display[i]) do
      count = tab.count(display[i])
      if count == 0 or nil then return
      else
        if i % 2 == 0 then
          if display[i][count][n] == 1 then
            g:led(n, i, 8)
          else
            g:led(n, i, 2)
          end
          g:led((q_position % count) + 1, i, 15)
        end
      end
    end
  end

  g:refresh()
end



----------------------
-- save/load functions
----------------------
function save_preset()
  tab.save(track, norns.state.data .. "preset-" .. preset_select .. ".data")
  -- print("SAVE COMPLETE")
end

function load_preset()
  local temp = tab.load(norns.state.data .. "preset-".. preset_select .. ".data")
  if temp then
    track = temp
    -- print("LOAD COMPLETE")
  else
    -- print("LOAD FAILED: preset doesn't exist")
  end
end

function preview_preset()
  local temp = tab.load(norns.state.data .. "preset-".. preset_select .. ".data")
  if temp then
    preview = temp
    -- print("preview exists")
  else
    preview = {}
  end
end



------------------------
-- convenience functions
------------------------
function update_cursor(dimension, delta)
  -- should only be called in "edit" mode
  -- because of tab.count on buffer
  local max_length = 16
  if row_select % 2 == 1 then
    max_length = 15
  end

  -- change selected row (1-8)
  if dimension == "row" then
    row_select = (row_select + delta) % 8
    if row_select == 0 then
      row_select = 8
    end
    -- print("row "..row_select)
    length_select = tab.count(buffer[row_select])
    if sub_select > length_select then
      sub_select = length_select
    end
    cursor = {row_select, length_select, sub_select}

  -- change subdivision amount of selected row
  elseif dimension == "length" then
    length_select = util.clamp((length_select + delta), 1, max_length)
    -- print("length "..length_select)
    if length_select < sub_select then
      sub_select = length_select
    end
    cursor = {row_select, length_select, sub_select}
    -- initialize row when length is changed
    buffer[row_select] = {}
    for i = 1, length_select do
      buffer[row_select][i] = {}
      for j=1, i do
        buffer[row_select][i][j] = 1
      end
    end

  -- change selected subdivision
  elseif dimension == "column" then
    length_select = tab.count(buffer[row_select])
    sub_select = (sub_select + delta) % (length_select)
    if sub_select == 0 then
      sub_select = length_select
    end
    -- print("sub "..sub_select)
    cursor = {row_select, length_select, sub_select}
  else
    return
  end
end

function discard_changes()
  -- print("buffer discarded")
  buffer = {}
end

function apply_changes()
  -- print("buffer applied")
  track = buffer
  buffer = {}
end

function stop_clock()
  clk:stop()
  running = false
  for i=1, 4 do
    all_notes_off(i)
  end
end

function reset_clock()
  position = 0
  clk:start()
  running = true
end

function deepcopy(tab)
  -- taken from Lua user's wiki
  local tab_type = type(tab)
  local copy
  if tab_type == 'table' then
    copy = {}
    for tab_key, tab_value in next, tab, nil do
      copy[deepcopy(tab_key)] = deepcopy(tab_value)
    end
    setmetatable(copy, deepcopy(getmetatable(tab)))
  else -- number, string, boolean, etc
    copy = tab
  end
  return copy
end

function load_random(track)
  local files
  local filename = params:string(track.."_sample")
  if filename ~= "-" then
    files = GetSiblings(params:get(track.."_sample"), filename)
    engine.loadSample(track-1, files[math.random(1, #files)])
  end
end

function GetSiblings(file_path, file_name)
  local dir = string.gsub(file_path, escape(file_name), "")
  local files = {}
  local temp = norns.state.data.."files.txt"
  os.execute('ls -1 '..dir..' > '..temp)
  local f = io.open(temp)
  if not f then return files end
  local k = 1
  for line in f:lines() do
    files[k] = dir..line
    k = k + 1
  end
  f:close()
  return files
end

function escape (s)
  s = string.gsub(s, "[%p%c]", function (c)
    return string.format("%%%s", c) end)
  return s
end