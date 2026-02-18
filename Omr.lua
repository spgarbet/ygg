engine.name = 'Ygg'

-- For play demo
local notes = {48, 52, 55, 58, 60, 64, 66}  -- C11 chord (C, E, G, Bb, C, E, F#)
local step = 0

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
    names = { "attack", "release", "hold", "harmonics", "vibrato_depth", "mod_depth" },
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
  return function(x) engine.vibrato_depth_v(v_idx - 1, x) end
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

  params:add_option("ygg_lfo_style", "lfo_style",
    { "Sine A", "A+B Mix", "Ring Mod", "Slewed Ring" }, 1)
  params:set_action("ygg_lfo_style", send_lfo)

  params:add_group("Ygg: Voice", 16)

  for i = 1, 8 do
    params:add
    {
      type        = "control",
      id          = "ygg_vib_" .. i,
      name        = "Vib " .. i,
      controlspec = controlspec.new(0.0, 0.1, 'lin', 0.001, 0.01, ""),
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

  params:bang()
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
    label  = "Vib" .. i,
    id     = "ygg_vib_" .. i,
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
    { label = "Att",  id = "ygg_attack"    },
    { label = "Rel",  id = "ygg_release"   },
    { label = "Hld",  id = "ygg_hold"      },
    { label = "Har",  id = "ygg_harmonics" },
    { label = "Dpth", id = "ygg_mod_depth" },
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
-- init
-- ============================================================

function init()
  engine.attack(10.0)
  engine.release(3.0)
  engine.hold(0.0)
  engine.harmonics(0.5)
  engine.mod_depth(0.3)
  engine.routing(0)

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
  add_params()
end

-- ============================================================
-- Playback helpers
-- ============================================================

function play()
  if step < 0 then
    engine.note_off(notes[step + #notes + 1])
  else
    engine.note_on(notes[step + 1], 80)
  end

  step = step + 1
  if step >= #notes then
    step = -#notes
  end
end

function panic()
  -- NEED TO HALT ALL VOICES HERE
end

-- ============================================================
-- Keys
-- ============================================================

function key(n, z)
  if z ~= 1 or n == 1 then return end

  if n == 2 then
    if page > 1 then
      page = page - 1
    else
      panic()
    end
  end

  if n == 3 then
    if page < #page_name then
      page = page + 1
    else
      play()
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
    if n == 2 then
      row   = util.clamp(row - (d > 0 and 1 or -1), 1, ROWS)
      patch = (row - 1) * COLS + col
    elseif n == 3 then
      col   = util.clamp(col + (d > 0 and 1 or -1), 1, COLS)
      patch = (row - 1) * COLS + col
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
  screen.text("K2: Panic")
  screen.move(2, 32)
  screen.text("K3: Config")
  screen.move(2, 42)
  screen.text("E2: ^ or v")
  screen.move(2, 52)
  screen.text("E3: < or >")
end

function draw_demo()
  screen.level(15)
  screen.move(2, 32)
  screen.text("K3: Do Something")
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

