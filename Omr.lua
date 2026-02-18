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
local patch_name  = { 'Sol',  'Mani', 'Huginn', 'Muninn', 'Asgard', 'Midgard', 'Jormun', 'Gandr' }
local page_name   = { 'Ygg', 'LFO', 'Delay', 'Dist', 'Demo' }

-- STATE Current lattice position (col and row, 1-indexed)
local col   = 1
local row   = 1
local patch = 1

-- STATE Blink state
local blink = false
local blink_timer

-- STATE Current Page / Local Param
local page = 1
local lfo_param = 1

-- Params
local specs =
{
  -- Voice globals
  ["attack"]        = controlspec.new(0.001, 10.0, 'exp', 0,     10.0, "s"),
  ["release"]       = controlspec.new(0.001, 10.0, 'exp', 0,      3.0, "s"),
  ["hold"]          = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.0, ""),
  ["harmonics"]     = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.5, ""),
  ["vibrato_depth"] = controlspec.new(0.0,   0.1,  'lin', 0.001,  0.01,""),
  ["mod_depth"]     = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.3, ""),
  -- LFO
  ["lfo_freq_a"]    = controlspec.new(0.01, 20.0,  'exp', 0,      0.1, "Hz"),
  ["lfo_freq_b"]    = controlspec.new(0.01, 20.0,  'exp', 0,      0.2, "Hz"),
  -- Delay
  ["delay_time_1"]  = controlspec.new(0.001, 2.0,  'lin', 0.001,  0.25, "s"),
  ["delay_time_2"]  = controlspec.new(0.001, 2.0,  'lin', 0.001,  0.50, "s"),
  ["delay_fb"]      = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.3, ""),
  ["delay_mix"]     = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.3, ""),
  ["delay_mod_1"]   = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.0, ""),
  ["delay_mod_2"]   = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.0, ""),
  -- Distortion
  ["dist_drive"]    = controlspec.new(1.0,  10.0,  'lin', 0.1,    1.0, ""),
  ["dist_mix"]      = controlspec.new(0.0,   1.0,  'lin', 0.01,   0.0, ""),
}

-- Groups define separators and control the initialization order.
-- Params that share a multi-argument engine command are grouped
-- together so their joint action can read sibling values cleanly.
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

-- Actions for params that share a multi-argument engine command.
-- These are called instead of the default engine[p_name](x) path.
local function send_lfo()
  engine.lfo(
    params:get("ygg_lfo_freq_a"),
    params:get("ygg_lfo_freq_b"),
    params:get("ygg_lfo_style") - 1   -- convert 1-based option to 0-based int
  )
end

local function send_delay_time()
  engine.delay_time(params:get("ygg_delay_time_1"), params:get("ygg_delay_time_2"))
end

local function send_delay_mod()
  engine.delay_mod(params:get("ygg_delay_mod_1"), params:get("ygg_delay_mod_2"))
end

-- Map param ids to a custom action where needed;
-- anything not listed here falls back to engine[p_name](x).
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

  -- Option params sit outside the control loop since they are not
  -- controlspec-based, but they still belong to their logical group.
  params:add_option("ygg_routing",   "routing",
    { "Self", "Cross", "Neighbor", "Rotate" }, 1)
  params:set_action("ygg_routing",
    function(v) engine.routing(v - 1) end)

  params:add_option("ygg_lfo_style", "lfo_style",
    { "Sine A", "A+B Mix", "Ring Mod", "Slewed Ring" }, 1)
  params:set_action("ygg_lfo_style", send_lfo)

  params:bang()
end

function init()
  -- Initialize engine parameters
  engine.attack(10.0)
  engine.release(3.0)
  engine.hold(0.0)
  engine.harmonics(0.5)
  engine.mod_depth(0.3)
  engine.routing(0)

  tree = screen.load_png(_path.code .. "ygg/img/tree.png")
  assert(tree, "tree.png failed to load")

  -- Start blink metro
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

function play()
  -- Turn a note on or off
  if step < 0 then
    engine.note_off(notes[step + #notes + 1])
  else
    engine.note_on(notes[step + 1], 80)
  end

  -- Advance step
  step = step + 1
  if step >= #notes then
    step = -#notes
  end
end

function panic()
  -- NEED TO HALT ALL VOICES HERE
end

function key(n, z)
  -- Only handle K2, K3 press (not release)
  if z ~= 1 or n == 1 then
    return
  end

  -- Forward 
  if n == 2 then
    if page < #page_name then
      page = page + 1
    else -- Last demo/play screen do action
      play()
    end
  end 

  -- Backward
  if n == 3 then
    if page > 1 then
      page = page - 1
    else
      panic()
    end
  end

  redraw()
end

function enc(n, d)
  if page_name[page] == 'Ygg' then
    if n == 2 then
      -- E2: move up/down (rows), no wrap
      row    = util.clamp(row - (d > 0 and 1 or -1), 1, ROWS)
      patch  = (row-1)*COLS+col
    elseif n == 3 then
      -- E3: move left/right (columns), no wrap
      col = util.clamp(col + (d > 0 and 1 or -1), 1, COLS)
      patch  = (row-1)*COLS+col
    end
  elseif page_name[page] == 'LFO' then
    if n == 2 then
      lfo_param = util.clamp(lfo_param + (d > 0 and 1 or -1), 1, 3)
    elseif n == 3 then
      if lfo_param == 1 then
        params:delta("ygg_lfo_style", d)
      elseif lfo_param == 2 then
        params:delta("ygg_lfo_freq_a", d)
      elseif lfo_param == 3 then
        params:delta("ygg_lfo_freq_b", d)
      end
    end 
  end
  redraw()
end

local function draw_star(x, y)
  -- Draw 4 lines through center: horizontal, vertical, and two diagonals
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
  -- Draw blinking star at current position
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

  -- Left half label
  screen.level(15)
  screen.move(2, 22)
  screen.text("K2: Config")
  screen.move(2, 32)
  screen.text("K3: Panic")
  screen.move(2, 42)
  screen.text("E2: ^ or v")
  screen.move(2, 52)
  screen.text("E3: < or >")
end

function draw_LFO()
  local style_names = { "Sine A", "A+B Mix", "Ring Mod", "Slewed" }
  local style       = params:get("ygg_lfo_style")
  local freq_a      = params:get("ygg_lfo_freq_a")
  local freq_b      = params:get("ygg_lfo_freq_b")

  local labels  = { "Style", "FreqA", "FreqB" }
  local values  = { style_names[style], string.format("%.2f Hz", freq_a), string.format("%.2f Hz", freq_b) }

  for i = 1, 3 do
    local y = 32 + ((i - 1) * 10)

    screen.level(lfo_param == i and 15 or 4)
    screen.move(2, y)
    screen.text(labels[i])

    screen.level(lfo_param == i and 15 or 10)
    screen.move(30, y)
    screen.text(values[i])
  end 
end

function draw_demo()
  screen.level(15)
  screen.move(2, 32)
  screen.text("K2: Do Something")
end

function redraw()
  screen.clear()

  screen.level(15)
  screen.move(2, 12)
  screen.text(patch_name[patch])

  if page > 1 then
    screen.move(126, 12)
    screen.text_right(page_name[page])
  end

  if page_name[page] == 'Ygg' then
    screen.display_image(tree, 64, 0)
    draw_ygg()
  end
  
  if page_name[page] == 'LFO' then
    draw_LFO()
  end
  
  if page_name[page] == 'Demo' then
    draw_demo()
  end

  screen.update()
end
