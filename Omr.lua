-- Ygg C11 Chord Stepper
-- E2: Move Left/Right  E3: Move Up/Down  K3: Next Step

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
local page_name = { 'Ygg', 'LFO', 'Delay', 'Dist', 'V1', 'V2' , 'V3' , 'V4', 'V5' ,'V6', 'V7', 'V8', 'Demo' }

-- STATE Current lattice position (col and row, 1-indexed)
local col   = 1
local row   = 1
local patch = 1

-- STATE Blink state
local blink = false
local blink_timer

-- STATE Current Page
local page = 1

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
  if page == 1 then
    if n == 2 then
      -- E2: move left/right (columns), no wrap
      col = util.clamp(col + (d > 0 and 1 or -1), 1, COLS)
      patch  = (row-1)*COLS+col
      redraw()
    elseif n == 3 then
      -- E3: move up/down (rows), no wrap
      row    = util.clamp(row - (d > 0 and 1 or -1), 1, ROWS)
      patch  = (row-1)*COLS+col
      redraw()
    end
  end
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
  screen.text("E2: < or >")
  screen.move(2, 52)
  screen.text("E3: ^ or v")
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
  
  if page_name[page] == 'Demo' then
    draw_demo()
  end

  screen.update()
end


