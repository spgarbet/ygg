-- Randomly generated harmonic sequence using Sequins
-- Parameters: seed (number), tonic (midi note number), scale (string)

local SCALES =
{
  major         = {0, 2, 4, 5, 7, 9, 11},
  natural_minor = {0, 2, 3, 5, 7, 8, 10},
  bhairav       = {0, 1, 4, 5, 7, 8, 11},
  locrian       = {0, 1, 3, 5, 6, 8, 10}
}

-- Each voicing is exactly 8 intervals so the permutation always has 8 slots.

local CHORD_INTERVALS =
{
  I =
  {
    0,   -- root
    4,   -- major 3rd
    7,   -- perfect 5th
    11,  -- major 7th
    14,  -- 9th
    18,  -- #11th  (Lydian colour)
    21,  -- 13th
    24,  -- root + 2 octaves
  },
  II =
  {
    0,   -- chord root  (scale degree 2, offset applied below)
    3,   -- minor 3rd
    7,   -- perfect 5th
    10,  -- minor 7th
    14,  -- 9th
    17,  -- 11th
    20,  -- minor 13th
    24,  -- root + 2 octaves
  },
  V6 =
  {
    4,   -- major 3rd in the bass
    7,   -- perfect 5th
    10,  -- minor 7th  (dominant)
    12,  -- chord root
    14,  -- 9th
    18,  -- #11th  (Lydian dominant)
    21,  -- 13th
    24,  -- root + 2 octaves
  },
}

-- Returns a random permutation of integers 1..n
local function random_permutation(n)
  local t = {}
  for i = 1, n do t[i] = i end
  for i = n, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- Reorders a table according to a permutation index table
local function reorder(t, perm)
  local out = {}
  for i = 1, #perm do
    out[i] = t[perm[i]]
  end
  return out
end

-- Slices a 1-indexed table from a to b inclusive
local function slice(t, a, b)
  local out = {}
  for i = a, b do
    table.insert(out, t[i])
  end
  return out
end

-- Repeats a table n times into a flat list
local function rep(t, n)
  local out = {}
  for _ = 1, n do
    for _, v in ipairs(t) do
      table.insert(out, v)
    end
  end
  return out
end

-- Concatenates multiple tables into one flat list
local function concat(...)
  local out = {}
  for _, t in ipairs({...}) do
    for _, v in ipairs(t) do
      table.insert(out, v)
    end
  end
  return out
end

-- Builds an 8-note extended voicing as absolute MIDI note numbers.
-- tonic      : MIDI root of the key
-- root_offset: semitones above tonic to the chord root (e.g. 0 for I, 2 for II in major)
-- intervals  : the 8 chord-relative semitone intervals from CHORD_INTERVALS
local function build_voicing(tonic, root_offset, intervals)
  local notes = {}
  for i, interval in ipairs(intervals) do
    notes[i] = tonic + root_offset + interval
  end
  return notes
end

-- Builds 8 velocity values centred on `centre` with +/-15 random variation,
-- reordered by `perm` so velocity contour matches the note permutation.
-- Values are clamped to [1, 127].
local function build_velocities(centre, perm)
  local raw = {}
  for i = 1, 8 do
    raw[i] = math.max(1, math.min(127, centre + math.random(-15, 15)))
  end
  return reorder(raw, perm)
end

local function gen_sequence(seed, tonic, scale_name, attack_time, release_time)
  math.randomseed(seed)

  local scale = SCALES[scale_name]
  if not scale then
    print("Unknown scale: " .. tostring(scale_name))
    return
  end

  -- Chord roots derived from the scale (0-indexed semitone offsets above tonic)
  local root_I  = scale[1]  -- degree 1
  local root_II = scale[2]  -- degree 2
  local root_V  = scale[5] - 12  -- degree 5, dropped an octave so the 3rd-in-bass
                                  -- sits a half step below the tonic
  local root_VI = scale[6]       -- degree 6
  local root_III = scale[3]      -- degree 3


  -- Build raw 8-note extended voicings
  local I_raw  = build_voicing(tonic, root_I,  CHORD_INTERVALS.I)
  local II_raw = build_voicing(tonic, root_II, CHORD_INTERVALS.II)
  local V6_raw = build_voicing(tonic, root_V,  CHORD_INTERVALS.V6)
  local VI_raw  = build_voicing(tonic, root_VI,  CHORD_INTERVALS.I)   -- major 13 voicing
  local III_raw = build_voicing(tonic, root_III, CHORD_INTERVALS.I)   -- major 13 voicing

  -- Apply the same random permutation to all three chords so the
  -- rhythmic contour is shared across harmonic areas
  local perm = random_permutation(8)
  local I   = reorder(I_raw,  perm)
  local II  = reorder(II_raw, perm)
  local V6  = reorder(V6_raw, perm)
  local VI  = reorder(VI_raw,  perm)
  local III = reorder(III_raw, perm)

  local VI_slice  = slice(VI,  s, s + 3)
  local III_slice = slice(III, s, s + 3)

  -- Build wait times
  -- Total window = attack_time * 8; 7 random interior points divide it into 8 intervals
  local total_time = attack_time * 8
  local pts = {}
  for i = 1, 7 do pts[i] = math.random() * total_time end
  table.sort(pts)

  local wait = {}
  local prev = 0
  for i = 1, 7 do
    wait[i] = pts[i] - prev
    prev     = pts[i]
  end
  wait[8] = total_time - prev

  -- Pick random slice start (1..5 so that slice+3 <= 8)
  local s = math.random(1, 5)

  -- Note stack: {I, V6, I[s,s+3], I[s,s+3], V6[s,s+3], V6[s,s+3], II, V6, I}
  -- = 8+8+4+4+4+4+8+8+8 = 56 notes
  local I_slice  = slice(I,  s, s + 3)
  local V6_slice = slice(V6, s, s + 3)

  local note_stack = concat(
    I,
    V6,
    I_slice,    -- I slice repeat 1
    VI_slice,   -- I slice repeat 2 -> transposed to VI
    V6_slice,   -- V6 slice repeat 1
    III_slice,  -- V6 slice repeat 2 -> transposed to III
    II,
    V6,
    I
  )

  -- Time stack breakdown (56 slots matching the 7 sections of 8 notes each):
  --   I       (8)  -> wait
  --   V6      (8)  -> wait
  --   I[s]x2  (8)  -> wait[s..s+3]/2  repeated across both repeats
  --   V6[s]x2 (8)  -> wait[s..s+3]/2  repeated across both repeats
  --   II      (8)  -> wait
  --   V6      (8)  -> wait
  --   I       (8)  -> 1 second each
  local wait_slice_halved = {}
  for i = s, s + 3 do
    table.insert(wait_slice_halved, wait[i] / 2)
  end

  local time_stack = concat(
    wait,
    wait,
    rep(wait_slice_halved, 4),
    wait,
    wait,
    rep({1}, 8)
  )

  -- Velocity stacks, one 8-value array per section, each centred and permuted.
  -- Sections:
  --   I        centre 60  (section 1)
  --   V6       centre 75  (section 1 + 15)
  --   I[s]     centre 40  (slice section offsets: 40, 55, 65, 55)
  --   I[s]     centre 55
  --   V6[s]    centre 65
  --   V6[s]    centre 55
  --   II       centre 55
  --   V6       centre 80
  --   I        centre 40
  --
  -- Each base velocity array is 8 values; sliced sections use indices s..s+3.

  local vel_I_a   = build_velocities(60, perm)   -- section 1 I
  local vel_V6_a  = build_velocities(75, perm)   -- section 1 V6
  local vel_Is1   = build_velocities(40, perm)   -- I slice repeat 1
  local vel_Is2   = build_velocities(55, perm)   -- VI slice repeat 2
  local vel_V6s1  = build_velocities(65, perm)   -- V6 slice repeat 1
  local vel_V6s2  = build_velocities(55, perm)   -- III slice repeat 2
  local vel_II    = build_velocities(55, perm)   -- II section
  local vel_V6_b  = build_velocities(80, perm)   -- closing V6
  local vel_I_b   = build_velocities(40, perm)   -- closing I

  local vel_stack = concat(
    vel_I_a,
    vel_V6_a,
    slice(vel_Is1,  s, s + 3),
    slice(vel_Is2,  s, s + 3),
    slice(vel_V6s1, s, s + 3),
    slice(vel_V6s2, s, s + 3),
    vel_II,
    vel_V6_b,
    vel_I_b
  )

  assert(#note_stack == 56, "note stack length mismatch: " .. #note_stack)
  assert(#time_stack == 56, "time stack length mismatch: " .. #time_stack)
  assert(#vel_stack  == 56, "vel stack length mismatch: "  .. #vel_stack)

  return {notes = note_stack, times = time_stack, velocities = vel_stack}
end

local function play_sequence(note_stack, time_stack, vel_stack)
  -- Play the sequence using a coroutine clock
  local note_seq = sequins(note_stack)
  local time_seq = sequins(time_stack)
  local vel_seq  = sequins(vel_stack)

  clock.run(function()
    for _ = 1, 56 do
      local note     = note_seq()
      local wait_dur = time_seq()
      local vel      = vel_seq()
      engine.noteOn(note, vel, 0)
      clock.sleep(wait_dur)
    end
    for i = 49, 56 do
      engine.noteOff(note_stack[i])
      clock.sleep(release_time)
    end
  end)
end

return gen_sequence
