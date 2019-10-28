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
-- enc2: select pattern
-- enc3: filter cutoff
--
-- key1: save pattern
-- key2: load pattern
-- key3: stop clock
-- key3: HOLD->EDIT MODE
--
-- EDIT MODE
-- enc1: track select
-- enc2: subdiv. select
-- enc3: length select
--
-- key1: save pattern
-- key2: load pattern
-- key3: toggle subdiv. on/off
-- key3: HOLD->PLAY MODE
-- ---------------------------------------------



engine.name = 'Ack'

local ack = require 'ack/lib/ack'

local g = grid.connect()

local BeatClock = require '/home/we/dust/code/ekombi/ebeatclock'
local clk = BeatClock.new()
local clk_midi = midi.connect()
clk_midi.event = clk.process_midi



------------
-- variables
------------



-- clocking variables
local position = 0
local q_position = 0
local counter = nil

local running = false

-- midi variables
midi_out_device = {1, 1, 1, 1}
midi_out_channel = {1, 1, 1, 1}
midi_out_note = {64, 64, 64, 64}
midi_notes_on = {{},{},{},{}}


-- pattern variables
local pattern_select = 1

-- display variables
local pattern_display = "default"

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

-- 4, two-track channels (A is even rows, TrackB is odd rows)
local track = {}
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
  clk:add_clock_params()

  params:add_separator()

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
    ack.add_channel_params(channel)

    params:add_separator()

  end

  params:read("ekombi.pset")

  -- metronome setup
  clk.on_step = step
  clk.on_select_internal = function() clk:start() end
  clk.on_select_external = reset_pattern
  clk.on_tick = tick

  clk:add_clock_params()
  -- counter:start()
  blink = 0
  blinker = metro.init()
  blinker.time = 1/11
  blinker.count = -1
  blinker.event = function(b)
    blink = blink + 1
    redraw()
  end

  connect_midi()
  gridredraw()
  redraw()
end

function connect_midi()
  for channel=1, 4 do
    midi_out_device[channel] = midi.connect(params:get(channel.. "_midi_out_device"))
  end
end

local function all_notes_off(channel)
  for i = 1, #midi_notes_on[channel] do
    midi_out_device[channel]:note_off(midi_notes_on[i])
  end
  midi_notes_on[channel] = {}
end

local mode = 0



-------------------------
-- grid control functions
-------------------------



function g.key(x, y, z)
  -- sending data to two separate functions
  gridkeyhold(x,y,z)
  gridkey(x,y,z)
  print(x,y,z)
end

function gridkey(x,y,z)
  if z == 1 then
    cnt = #(track[y])

    -- error control
    if cnt == 0 or cnt == nil then
      if x > 1 then
        return
      elseif x == 1 then
        track[y] = {}
        track[y][x] = {}
        track[y][x][x] = 1
        gridredraw()
      end
      return

    else
      -- track-B un-reset-able
      if x == 16 and y % 2 == 1 then
        track[y] = {}
        track[y][1] = {}
        track[y][1][1] = 0
        return
      end

      -- note toggle on/off
      if x > cnt then
        return
      else
        if track[y][cnt][x] == 1 then
          track[y][cnt][x] = 0
        else
          track[y][cnt][x] = 1
        end
      end

      -- automatic clock startup
      if running == false then
        clk:start()
        running = true
      end

    end
  end
  redraw()
  gridredraw()
end



function gridkeyhold(x, y, z)
  if z == 1 and g_held[y] then g_heldMax[y] = 0 end
  g_held[y] = g_held[y] + (z*2 -1)

  if g_held[y] > g_heldMax[y] then g_heldMax[y] = g_held[y] end

  if y > 8 and g_held[y] == 1 then
    first[y] = x
  elseif y <= 8 and g_held[y] == 2 then
    second[y] = x
  elseif z == 0 then
    if y <= 8 and g_held[y] == 1 and g_heldMax[y] == 2 then
      track[y] = {}
      for i = 1, second[y] do
        track[y][i] = {}
        for n=1, i do
          track[y][i][n] = 1
        end
      end
    end
  end

  redraw()
  gridredraw()
end



---------------------------
-- norns control functions
---------------------------

local track_select = 0 -- 0 indexed, then +1'd later
local sub_select = 0
-- length_select is 1 indexed because it is modified in two different places
-- in two different ways, one uses the table counting method which itself counts in 1-index
local length_select = 1 -- no track-lengths of 0,
local cursor = {track_select+1,length_select,sub_select+1}

function enc(n,d)
  if n == 1 then
    if mode == 0 then
      params:delta("bpm",d)
    else
      track_select = (track_select + d) % 8
      length_select = #(track[track_select+1])
      print("track "..track_select+1)
      sub_select = 0
      cursor = {track_select+1,length_select,sub_select+1}
    end
  end

  if n == 2 then
    if mode == 0 then
      pattern_select = util.clamp(pattern_select + d, 1, 16)
      print("pattern:"..pattern_select)
    else
      sub_select = (sub_select + d) % (length_select)
      print("sub "..sub_select+1)
      cursor = {track_select+1,length_select,sub_select+1}
    end
  end

  if n == 3 then
    if mode == 0 then
      for i=1, 4 do
        params:delta(i.."_filter_cutoff", d)
      end
    else
      length_select = ((length_select + d) % 16)
      if length_select == 0 then length_select = 16 end -- I really didn't want to do this.
      print("length "..length_select)
      cursor = {track_select+1,length_select,sub_select+1}
      track[track_select+1] = {}
      for i = 1, length_select do
        track[track_select+1][i] = {}
        for j=1, i do
          track[track_select+1][i][j] = 1
        end
      end
    end
  end

  redraw()
end

function key(n,z)

  if z == 1 then

    if n == 1 then
      save_pattern()
    end

    if n == 2 or n == 3 then
      key_held = util.time()
    end

  else

    if n == 2 then
      if key_held - util.time() < -0.333 then -- hold for a third of a second
        load_pattern()
        pattern_display = pattern_select
      end
    end

    if n == 3 then
      if key_held - util.time() < -0.333 then -- hold for a third of a second
        mode = (mode + 1) % 2
        print("mode "..mode)
        blinker:start()
      else
        if mode == 0 then
          blinker:stop()
          if running then
            clk:stop()
            running = false
            for i=1, 4 do
              all_notes_off(i)
            end
          else
            position = 0
            clk:start()
            running = true
          end
        else
          track[track_select+1][length_select][sub_select+1] = (track[track_select+1][length_select][sub_select+1] + 1) % 2
        end
      end
    end
  end

  gridredraw()
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

function step()
  q_position = q_position + 1
  fast_gridredraw()
end

function tick()
  local ppq = clk.steps_per_beat * clk.ticks_per_step
  position = (position + 1) % ppq
  local pending = {}
  for i=2, 8, 2 do
    cnt = #(track[i])
    if cnt == 0 or cnt == nil then
      return
    else
      if track[i][cnt][(q_position % cnt)+1] == 1 then
        table.insert(pending,i-1)
      end
    end
  end

  if #(pending) > 0 then
    for i=1, #(pending) do
      cnt = #(track[pending[i]])
      if cnt == 0 or cnt == nil then
        return
      else
        for n=1, cnt do
          if position / ( ppq // (#(track[pending[i]][cnt]))) == n-1 then
            if track[pending[i]][cnt][n] == 1 then
              t = (pending[i]//2) + 1
              engine.trig(t - 1) -- samples are 0-3
              all_notes_off(t)
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
  screen.clear()
  screen.aa(0)

  screen.level(15)
  -- grid pattern preset display
  for i=1, 8 do
    for n=1, #(track[i]) do
      if track[i][#(track[i])][n] == 1 then
        if mode == 1 and cursor[1] == i and cursor[3] == n and blink % 3 == 0 then
          -- pass                   blinking cursor to show selection in edit mode
        else
          screen.rect((n-1)*7, 1 + i*7, 6, 6)
        end
        screen.fill()
        screen.move(#(track[i])*7, i*7 + 7)
        screen.text(#(track[i]))
      else
        if mode == 1 and cursor[1] == i and cursor[3] == n and blink % 3 == 0 then
          -- pass
        else
          screen.rect(1 + (n-1)*7, 2 + i*7, 5, 5)
        end
        screen.stroke()
        screen.move(#(track[i])*7, 7 + i*7)
        screen.text(#(track[i]))
      end
    end
  end

  -- param display
  screen.move(0,5)
  screen.text("bpm:"..params:get("bpm"))
  screen.move(64,5)
  screen.level(15)
  screen.text_center("pattern:"..pattern_select)

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

  screen.level(1)
  -- currently selected pattern
  screen.move(128,5)
  screen.text_right(pattern_display)

  screen.update()
end

function gridredraw()
  g:all(0)

  -- draw channels with sub divisions on/off
  for i=1, 8 do
    for n=1, #(track[i]) do
      ct = #(track[i])
      if ct == 0 or nil then return
      else
        if i % 2 == 1 then
          if track[i][ct][n] == 1 then
            g:led(n, i, 12)
          else
            g:led(n, i, 4)
          end

        elseif i % 2 == 0 then
          if track[i][ct][n] == 1 then
            g:led(n, i, 8)
          else
            g:led(n, i, 2)
          end
          g:led((q_position % ct) + 1, i, 15)
        end
      end
    end
  end

  g:refresh()
end

function fast_gridredraw()

  for i=1, 8 do
    for n=1, #(track[i]) do
      ct = #(track[i])
      if ct == 0 or nil then return
      else
        if i % 2 == 0 then
          if track[i][ct][n] == 1 then
            g:led(n, i, 8)
          else
            g:led(n, i, 2)
          end
          g:led((q_position % ct) + 1, i, 15)
        end
      end
    end
  end

  g:refresh()
end



------------------
-- save/load functions
----------------------

function save_pattern()
  tab.save(track, data_dir .. "ekombi/pattern-" .. pattern_select .. ".data")
  print("SAVE COMPLETE")
end

function load_pattern()
  track = tab.load(data_dir .. "ekombi/pattern-".. pattern_select .. ".data")
  print("LOAD COMPLETE")
end
