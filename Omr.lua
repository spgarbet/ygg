engine.name = 'Ygg'

local gen_sequence = require('ygg/lib/gen_sequence')

-- File paths
local SAVE_DIR      = _path.data .. "ygg/"
local SAVE_FILE     = SAVE_DIR .. "patches.txt"
local DEFAULT_FILE  = _path.code .. "ygg/patches_default.txt"

-- Preload image
local tree

-- Main log lattice coordinates
local COLS        = 2
local ROWS        = 4
local grid_x      = { 15, 48, 17, 46, 17, 46, 24, 38 }
local grid_y      = {  9,  9, 22, 22, 39, 39, 53, 53 }
local patch_name  = { 'Sol', 'Mani', 'Huginn', 'Muninn', 'Asgard', 'Midgard', 'Jormun', 'Gandr' }
local page_name   = { 'Ygg', 'Ginnun', 'LFO', 'Delay', 'Dist', 'Voice', 'Demo' }

-- Screen layout constants
local ROWS_VISIBLE = 4   -- how many param rows fit between the header and bottom
local ROW_Y_START  = 22  -- y of the first param row
local ROW_HEIGHT   = 10  -- px between rows
local LABEL_X      = 2
local VALUE_X      = 30
local ARROW_X      = 122 -- x for scroll indicators (right-aligned)

-- STATE Current lattice position (col and row, 1-indexed)
local col   = 1
local row   = 1
local patch = 1

-- STATE Blink state
local blink = false
local blink_timer

-- STATE Current page
local page = 1

-- STATE Per-page selected param index (1-based); one entry per page_name entry
local page_sel = { 1, 1, 1, 1, 1, 1, 1 }

-- STATE Demo
local demo_playing    = false
local demo_clock_id   = nil
local scale_names     = { "major", "natural_minor", "bhairav", "locrian" }
local note_names      = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

-- Demo params are local state only — not part of the patch system
local demo_seed       = 42
local demo_tonic      = 48   -- C3
local demo_scale_idx  = 1    -- index into scale_names
local demo_attack     = 0.4  -- seconds per note slot
local demo_sel        = 1    -- selected row on demo page (1-based)

-- STATE MIDI
-- ch_to_note maps MIDI channel (2-16) to the note currently playing on it.
-- This lets pitch bend and pressure messages find the right engine voice.
local midi_devices = {}
local ch_to_note   = {}

-- ============================================================
-- Params
-- ============================================================

local specs =
{
  ["attack"]        = controlspec.new(0.001, 20.0, 'exp', 0,     10.0, "s"),
  ["release"]       = controlspec.new(0.001, 20.0, 'exp', 0,      3.0, "s"),
  ["hold"]          = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.0, ""),
  ["harmonics"]     = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.5, ""),
  ["vibrato_depth"] = controlspec.new(0.0,   0.1,  'lin', 0.001,  0.01,""),
  ["mod_depth"]     = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.3, ""),
  ["lfo_freq_a"]    = controlspec.new(0.01, 20.0,  'exp', 0,      0.1, "Hz"),
  ["lfo_freq_b"]    = controlspec.new(0.01, 20.0,  'exp', 0,      0.2, "Hz"),
  ["delay_time_1"]  = controlspec.new(0.001, 2.0,  'lin', 0.001,  0.25, "s"),
  ["delay_time_2"]  = controlspec.new(0.001, 2.0,  'lin', 0.001,  0.50, "s"),
  ["delay_fb"]      = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.3, ""),
  ["delay_mix"]     = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.3, ""),
  ["delay_mod_1"]   = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.0, ""),
  ["delay_mod_2"]   = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.0, ""),
  ["dist_drive"]    = controlspec.new(1.0,  11.0,  'lin', 1.0,    1.0, ""),
  ["dist_mix"]      = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.0, ""),
}

local param_groups =
{
  {
    label = "Voice",
    names = { "attack", "release", "hold", "harmonics", "mod_depth" },
  },
  {
    label = "LFO",
    names = { "lfo_freq_a", "lfo_freq_b" },
  },
  {
    label = "Delay",
    names = { "delay_time_1", "delay_time_2", "delay_fb", "delay_mix", "delay_mod_1", "delay_mod_2" },
  },
  {
    label = "Distortion",
    names = { "dist_drive", "dist_mix" },
  },
}

local function send_lfo()
  engine.lfo(
    params:get("ygg_lfo_freq_a"),
    params:get("ygg_lfo_freq_b"),
    params:get("ygg_lfo_style") - 1
  )
end

local function send_delay_time()
  engine.delay_time(params:get("ygg_delay_time_1"), params:get("ygg_delay_time_2"))
end

local function send_delay_mod()
  engine.delay_mod(params:get("ygg_delay_mod_1"), params:get("ygg_delay_mod_2"))
end

local function send_vibrato_v(v_idx)
  return function(x) engine.vibrato_freq_v(v_idx - 1, x) end
end

local function send_mod_source_v(v_idx)
  return function(x) engine.voice_mod_source(v_idx - 1, x - 1) end
end

local custom_actions =
{
  ["lfo_freq_a"]   = send_lfo,
  ["lfo_freq_b"]   = send_lfo,
  ["delay_time_1"] = send_delay_time,
  ["delay_time_2"] = send_delay_time,
  ["delay_mod_1"]  = send_delay_mod,
  ["delay_mod_2"]  = send_delay_mod,
}

function add_params()
  for _, group in ipairs(param_groups) do
    params:add_group("Ygg: " .. group.label, #group.names)

    for _, p_name in ipairs(group.names) do
      params:add
      {
        type        = "control",
        id          = "ygg_" .. p_name,
        name        = p_name,
        controlspec = specs[p_name],
        action      = custom_actions[p_name] or function(x) engine[p_name](x) end,
      }
    end
  end

  params:add_option("ygg_routing", "routing",
    { "Self", "Cross", "Neighbor", "Loop" }, 1)
  params:set_action("ygg_routing",
    function(v) engine.routing(v - 1) end)

  params:add
  {
    type        = "control",
    id          = "ygg_vibrato_depth",
    name        = "vibrato_depth",
    controlspec = specs["vibrato_depth"],
    action      = function(x) engine.vibrato_depth(x) end,
  }

  params:add_option("ygg_lfo_style", "lfo_style",
    { "Sine A", "A+B Mix", "Ring Mod", "Slewed Ring" }, 1)
  params:set_action("ygg_lfo_style", send_lfo)

  params:add_group("Ygg: Per Voice", 16)

  for i = 1, 8 do
    params:add
    {
      type        = "control",
      id          = "ygg_vib_" .. i,
      name        = "Vib Freq " .. i,
      controlspec = controlspec.new(0.1, 20.0, 'exp', 0, 5.0, "Hz"),
      action      = send_vibrato_v(i),
    }
  end

  for i = 1, 8 do
    params:add_option(
      "ygg_mod_src_" .. i,
      "Mod " .. i,
      { "Voice", "LFO", "pre Delay", "Line Out" },
      1
    )
    params:set_action("ygg_mod_src_" .. i, send_mod_source_v(i))
  end
end

-- ============================================================
-- Page definitions
-- Each entry maps a page_name to a list of { label, param_id }
-- rows that draw_param_page and enc will use generically.
-- Option params carry a values[] list for display.
-- ============================================================

local style_names      = { "Sine A", "A+B Mix", "Ring Mod", "Slewed" }
local routing_names    = { "Self", "Cross", "Neighbor", "Loop" }
local mod_source_names = { "Voice", "LFO", "pre Delay", "Line Out" }

-- Build the Voice page rows programmatically to avoid repetition
local voice_rows = {}
for i = 1, 8 do
  voice_rows[#voice_rows + 1] =
  {
    label = "VibF" .. i,
    id    = "ygg_vib_" .. i,
  }
end
for i = 1, 8 do
  voice_rows[#voice_rows + 1] =
  {
    label  = "Mod" .. i,
    id     = "ygg_mod_src_" .. i,
    values = mod_source_names,
  }
end

local page_rows =
{
  ["Ginnun"] =
  {
    { label = "Att",  id = "ygg_attack"        },
    { label = "Rel",  id = "ygg_release"       },
    { label = "Hld",  id = "ygg_hold"          },
    { label = "Har",  id = "ygg_harmonics"     },
    { label = "Dpth", id = "ygg_mod_depth"     },
    { label = "VibD", id = "ygg_vibrato_depth" },
    { label = "Rout", id = "ygg_routing",  values = routing_names },
  },
  ["LFO"] =
  {
    { label = "Style", id = "ygg_lfo_style", values = style_names },
    { label = "FreqA", id = "ygg_lfo_freq_a" },
    { label = "FreqB", id = "ygg_lfo_freq_b" },
  },
  ["Delay"] =
  {
    { label = "T1",   id = "ygg_delay_time_1" },
    { label = "T2",   id = "ygg_delay_time_2" },
    { label = "FB",   id = "ygg_delay_fb"     },
    { label = "Mix",  id = "ygg_delay_mix"    },
    { label = "Mod1", id = "ygg_delay_mod_1"  },
    { label = "Mod2", id = "ygg_delay_mod_2"  },
  },
  ["Dist"] =
  {
    { label = "Drv", id = "ygg_dist_drive" },
    { label = "Mix", id = "ygg_dist_mix"   },
  },
  ["Voice"] = voice_rows,
}

-- ============================================================
-- Patch system
-- patch_ids is the canonical ordered list of every param that
-- belongs to a patch snapshot. It is built once from page_rows
-- so it stays automatically in sync if rows are ever added.
-- ============================================================

local patch_ids = {}
do
  -- Collect all unique param IDs from every page_rows entry
  local seen = {}
  for _, rows in pairs(page_rows) do
    for _, row_def in ipairs(rows) do
      if not seen[row_def.id] then
        patch_ids[#patch_ids + 1] = row_def.id
        seen[row_def.id] = true
      end
    end
  end
end

-- 8 patch slots; each is a table of { [param_id] = value }
-- Slots start empty and are populated on first save.
local patches = {}
for i = 1, 8 do
  patches[i] = {}
end

local function save_patch(slot)
  for _, id in ipairs(patch_ids) do
    patches[slot][id] = params:get(id)
  end
end

local function recall_patch(slot)
  -- Only recall if the slot has been saved at least once
  if next(patches[slot]) == nil then return end
  for _, id in ipairs(patch_ids) do
    if patches[slot][id] ~= nil then
      params:set(id, patches[slot][id])
    end
  end
end

-- Serialize patches to a simple flat text format.
-- Format: one line per value, "slot,key=value"
-- This avoids any external library dependency.
local function serialize_patches(p)
  local lines = {}
  for slot = 1, 8 do
    if p[slot] then
      for k, v in pairs(p[slot]) do
        lines[#lines + 1] = slot .. "," .. k .. "=" .. tostring(v)
      end
    end
  end
  return table.concat(lines, "\n")
end

local function deserialize_patches(text)
  local result = {}
  for i = 1, 8 do result[i] = {} end
  for line in text:gmatch("[^\n]+") do
    local slot, key, value = line:match("^(%d+),(.-)=(.+)$")
    if slot and key and value then
      slot = tonumber(slot)
      -- Restore numeric values; leave option integers as numbers
      local num = tonumber(value)
      result[slot][key] = num ~= nil and num or value
    end
  end
  return result
end

local function save_patches()
  util.make_dir(SAVE_DIR)
  local f = io.open(SAVE_FILE, "w")
  if f then
    f:write(serialize_patches(patches))
    f:close()
  else
    print("Ygg: could not write " .. SAVE_FILE)
  end
end

local function load_from_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local raw = f:read("*all")
  f:close()
  if not raw or raw == "" then return nil end
  local ok, result = pcall(deserialize_patches, raw)
  if ok then return result end
  print("Ygg: parse error in " .. path)
  return nil
end

local function load_patches()
  local loaded = load_from_file(SAVE_FILE)
  if loaded then patches = loaded ; return end

  loaded = load_from_file(DEFAULT_FILE)
  if loaded then patches = loaded ; return end
end

-- ============================================================
-- Generic param page value formatter
-- ============================================================

local function format_row(row_def)
  -- Option params carry a values table; everything else uses params:string()
  if row_def.values then
    return row_def.values[params:get(row_def.id)]
  end
  return params:string(row_def.id)
end

-- ============================================================
-- Generic scrollable param page draw
-- ============================================================

local function draw_param_page(pname)
  local rows   = page_rows[pname]
  local nrows  = #rows
  local sel    = page_sel[page]        -- selected row (1-based, global across all rows)
  -- Compute scroll offset so the selected row is always visible
  local offset = math.max(0, math.min(sel - 1, nrows - ROWS_VISIBLE))

  for slot = 1, ROWS_VISIBLE do
    local ri = offset + slot            -- actual row index
    if ri > nrows then break end

    local row_def = rows[ri]
    local y       = ROW_Y_START + (slot - 1) * ROW_HEIGHT
    local active  = (ri == sel)

    screen.level(active and 15 or 4)
    screen.move(LABEL_X, y)
    screen.text(row_def.label)

    screen.level(active and 15 or 10)
    screen.move(VALUE_X, y)
    screen.text(format_row(row_def))
  end

  -- Scroll indicators
  screen.level(6)
  if offset > 0 then
    screen.move(ARROW_X, ROW_Y_START)
    screen.text("^")
  end
  if offset + ROWS_VISIBLE < nrows then
    screen.move(ARROW_X, ROW_Y_START + (ROWS_VISIBLE - 1) * ROW_HEIGHT)
    screen.text("v")
  end
end

-- ============================================================
-- MIDI / MPE
-- Channel 1 = global zone (CC1 mod wheel)
-- Channels 2-16 = per-note voice channels
-- ============================================================

function midi_event(msg)
  local ch = msg.ch

  if msg.type == "note_on" and msg.vel > 0 then
    if ch >= 2 then
      ch_to_note[ch] = msg.note
      engine.note_on(msg.note, msg.vel)
    end

  elseif msg.type == "note_off" or
        (msg.type == "note_on" and msg.vel == 0) then
    if ch >= 2 then
      engine.note_off(msg.note)
      ch_to_note[ch] = nil
    end

  elseif msg.type == "pitchbend" then
    if ch >= 2 then
      local note = ch_to_note[ch]
      if note then
        -- Convert 14-bit pitchbend (0-16383, centre 8192) to semitones (-48 to +48)
        local bend_st = ((msg.val - 8192) / 8192) * 48
        engine.pitch_bend(note, bend_st)
      end
    end

  elseif msg.type == "aftertouch" then
    -- Per-note pressure (channel aftertouch on voice channel)
    if ch >= 2 then
      local note = ch_to_note[ch]
      if note then
        local pressure = msg.val / 127
        engine.pressure(note, pressure)
      end
    end

  elseif msg.type == "cc" then
    -- CC1 mod wheel on any channel maps to mod_depth
    if msg.cc == 1 then
      local depth = msg.val / 127
      params:set("ygg_mod_depth", depth)
    end
  end
end

-- ============================================================
-- init
-- ============================================================

function init()
  add_params()

  -- Connect to all available MIDI devices
  for i = 1, #midi.vports do
    midi_devices[i] = midi.connect(i)
    midi_devices[i].event = function(data)
      midi_event(midi.to_msg(data))
    end
  end

  tree = screen.load_png(_path.code .. "ygg/img/tree.png")
  assert(tree, "tree.png failed to load")

  blink_timer = metro.init(
    function()
      blink = not blink
      redraw()
    end,
    0.4,
    -1
  )
  blink_timer:start()
end

function engine_ready()
  params:bang()
  load_patches()
  recall_patch(patch)
end

-- ============================================================
-- Demo sequence playback
-- ============================================================

local function stop_sequence()
  if demo_clock_id then
    clock.cancel(demo_clock_id)
    demo_clock_id = nil
  end
  -- Release all voices cleanly
  for note = 0, 127 do
    engine.note_off(note)
  end
  demo_playing = false
end

local function play_sequence()
  stop_sequence()

  local seq = gen_sequence(
    demo_seed,
    demo_tonic,
    scale_names[demo_scale_idx],
    demo_attack
  )
  if not seq then return end

  demo_playing  = true
  local release = params:get("ygg_release")

  demo_clock_id = clock.run(function()
    local note_seq = sequins(seq.notes)
    local time_seq = sequins(seq.times)
    local vel_seq  = sequins(seq.velocities)

    for _ = 1, 56 do
      local note = note_seq()
      local wait = time_seq()
      local vel  = vel_seq()
      engine.note_on(note, vel)
      clock.sleep(wait)
    end

    -- Release the final held notes
    for i = 49, 56 do
      engine.note_off(seq.notes[i])
      clock.sleep(release / 8)
    end

    demo_playing  = false
    demo_clock_id = nil
    redraw()
  end)
end

-- ============================================================
-- Keys
-- ============================================================

function key(n, z)
  if z ~= 1 or n == 1 then return end

  if n == 2 then
    if page_name[page] == 'Ygg' then
      save_patch(patch)
      save_patches()
    elseif page > 1 then
      page = page - 1
    end
  end

  if n == 3 then
    if page_name[page] == 'Demo' then
      if demo_playing then
        stop_sequence()
      else
        play_sequence()
      end
    elseif page < #page_name then
      page = page + 1
    end
  end

  redraw()
end

-- ============================================================
-- Encoders
-- ============================================================

function enc(n, d)
  local pname = page_name[page]

  if pname == 'Ygg' then
    local prev_patch = patch
    if n == 2 then
      row   = util.clamp(row - (d > 0 and 1 or -1), 1, ROWS)
      patch = (row - 1) * COLS + col
    elseif n == 3 then
      col   = util.clamp(col + (d > 0 and 1 or -1), 1, COLS)
      patch = (row - 1) * COLS + col
    end
    if patch ~= prev_patch then
      recall_patch(patch)
    end

  elseif pname == 'Demo' then
    if n == 2 then
      demo_sel = util.clamp(demo_sel + (d > 0 and 1 or -1), 1, 4)
    elseif n == 3 then
      if demo_sel == 1 then
        demo_seed = math.max(1, demo_seed + d)
      elseif demo_sel == 2 then
        demo_tonic = util.clamp(demo_tonic + d, 24, 84)
      elseif demo_sel == 3 then
        demo_scale_idx = util.clamp(demo_scale_idx + (d > 0 and 1 or -1), 1, #scale_names)
      elseif demo_sel == 4 then
        demo_attack = util.clamp(demo_attack + (d * 0.05), 0.05, 2.0)
      end
    end

  elseif page_rows[pname] then
    -- Generic handler for all param pages
    local rows  = page_rows[pname]
    local nrows = #rows

    if n == 2 then
      page_sel[page] = util.clamp(page_sel[page] + (d > 0 and 1 or -1), 1, nrows)
    elseif n == 3 then
      local row_def = rows[page_sel[page]]
      params:delta(row_def.id, d)
    end
  end

  redraw()
end

-- ============================================================
-- Draw functions
-- ============================================================

local function draw_star(x, y)
  local s = 5
  screen.move(x - s, y)
  screen.line(x + s, y)
  screen.stroke()

  screen.move(x, y - s)
  screen.line(x, y + s)
  screen.stroke()

  local d = 3
  screen.move(x - d, y - d)
  screen.line(x + d, y + d)
  screen.stroke()

  screen.move(x + d, y - d)
  screen.line(x - d, y + d)
  screen.stroke()
end

function draw_ygg()
  local sx = grid_x[patch] + 64
  local sy = grid_y[patch]

  if blink then
    screen.level(1)
    screen.circle(sx, sy, 4)
    screen.fill()
    screen.level(15)
  else
    screen.level(1)
  end
  draw_star(sx, sy)

  screen.level(15)
  screen.move(2, 22)
  screen.text("K2: Save")
  screen.move(2, 32)
  screen.text("K3: Config")
  screen.move(2, 42)
  screen.text("E2: ^ or v")
  screen.move(2, 52)
  screen.text("E3: < or >")
end

function draw_demo()
  local tonic_name = note_names[(demo_tonic % 12) + 1]
  local tonic_oct  = math.floor(demo_tonic / 12) - 1

  local labels = { "Seed", "Root", "Scale", "Spd" }
  local values =
  {
    tostring(demo_seed),
    tonic_name .. tostring(tonic_oct),
    scale_names[demo_scale_idx],
    string.format("%.2f", demo_attack),
  }

  for i = 1, 4 do
    local y      = ROW_Y_START + (i - 1) * ROW_HEIGHT
    local active = (i == demo_sel)

    screen.level(active and 15 or 4)
    screen.move(LABEL_X, y)
    screen.text(labels[i])

    screen.level(active and 15 or 10)
    screen.move(VALUE_X, y)
    screen.text(values[i])
  end

  screen.level(15)
  screen.move(2, 62)
  screen.text(demo_playing and "K3: Stop" or "K3: Demo")
end

-- ============================================================
-- Redraw
-- ============================================================

function redraw()
  screen.clear()

  screen.level(15)
  screen.move(2, 12)
  screen.text(patch_name[patch])

  if page > 1 then
    screen.move(126, 12)
    screen.text_right(page_name[page])
  end

  local pname = page_name[page]

  if pname == 'Ygg' then
    screen.display_image(tree, 64, 0)
    draw_ygg()
  elseif pname == 'Demo' then
    draw_demo()
  elseif page_rows[pname] then
    draw_param_page(pname)
  end

  screen.update()
end
