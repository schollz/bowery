local INF = 10 ^ 15

local function copy_matrix(a)
  local out = {}
  for i = 1, #a do
    out[i] = {}
    for j = 1, #a[i] do
      out[i][j] = a[i][j]
    end
  end
  return out
end

local function prepare_cost(cost, maximize)
  if not maximize then
    return copy_matrix(cost)
  end

  local n, m = #cost, #cost[1]
  local maxv = -INF
  for i = 1, n do
    for j = 1, m do
      if cost[i][j] > maxv then
        maxv = cost[i][j]
      end
    end
  end

  local transformed = {}
  for i = 1, n do
    transformed[i] = {}
    for j = 1, m do
      transformed[i][j] = maxv - cost[i][j]
    end
  end
  return transformed
end

local function hungarian(cost, maximize)
  local n, m = #cost, #cost[1]
  if n ~= m then
    error("hungarian() expects NxN matrix")
  end
  local c = prepare_cost(cost, maximize)

  local u, v, p, way = {}, {}, {}, {}
  for i = 0, n do
    u[i] = 0
  end
  for j = 0, m do
    v[j], p[j], way[j] = 0, 0, 0
  end

  for i = 1, n do
    p[0] = i
    local j0 = 0
    local minv, used = {}, {}
    for j = 0, m do
      minv[j], used[j] = INF, false
    end

    repeat
      used[j0] = true
      local i0 = p[j0]
      local delta, j1 = INF, 0

      for j = 1, m do
        if not used[j] then
          local cur = c[i0][j] - u[i0] - v[j]
          if cur < minv[j] then
            minv[j], way[j] = cur, j0
          end
          if minv[j] < delta then
            delta, j1 = minv[j], j
          end
        end
      end

      for j = 0, m do
        if used[j] then
          u[p[j]] = u[p[j]] + delta
          v[j] = v[j] - delta
        else
          minv[j] = minv[j] - delta
        end
      end

      j0 = j1
    until p[j0] == 0

    repeat
      local j1 = way[j0]
      p[j0] = p[j1]
      j0 = j1
    until j0 == 0
  end

  local assign = {}
  for j = 1, m do
    if p[j] ~= 0 then
      assign[p[j]] = j
    end
  end
  return assign
end

local function sort_row_with_hungarian(row, maximize)
  local n = #row
  local target = {}
  for i = 1, n do
    target[i] = row[i]
  end
  table.sort(target)

  local cost = {}
  for i = 1, n do
    cost[i] = {}
    for j = 1, n do
      cost[i][j] = math.abs(row[i] - target[j])
    end
  end

  local assign = hungarian(cost, maximize)
  local sorted_row = {}
  for i = 1, n do
    sorted_row[assign[i]] = row[i]
  end
  return sorted_row
end

local function build_groups(matrix, maximize)
  local n = #matrix
  for i = 1, n do
    if #matrix[i] ~= n then
      error("matrix must be NxN")
    end
  end

  local sorted_rows = {}
  for i = 1, n do
    sorted_rows[i] = sort_row_with_hungarian(matrix[i], maximize)
  end

  local grouped = {}
  for col = 1, n do
    grouped[col] = {}
    for row = 1, n do
      grouped[col][row] = sorted_rows[row][col]
    end
  end
  return grouped
end

local rows = { {}, {}, {}, {} }
local notes = {}
local groups = { {}, {}, {}, {} }
local has_groups = false
local step_idx = 1
local BATCH_SIZE = 16
local GROUP_SIZE = 4
local GATE_INPUT = 1
local PITCH_INPUT = 2
local GATE_THRESHOLD = 1.0
local GATE_HYSTERESIS = 0.2
local HOLD_RESET_SECONDS = 5.0
local gate_on_seconds = nil

local function reset_capture()
  rows = { {}, {}, {}, {} }
  notes = {}
end

local function reset_learning_state(reason)
  reset_capture()
  groups = { {}, {}, {}, {} }
  has_groups = false
  step_idx = 1
  if reason then
    print("hungary: reset -> " .. reason)
  end
end

local function emit_all_outputs(volts)
  for i = 1, GROUP_SIZE do
    output[i].volts = volts
  end
end

local function emit_group_step()
  for i = 1, GROUP_SIZE do
    output[i].volts = groups[i][step_idx]
  end
  step_idx = step_idx + 1
  if step_idx > GROUP_SIZE then
    step_idx = 1
  end
end

local function capture_pitch(volts)
  notes[#notes + 1] = volts
  local idx = #notes
  local row = math.floor((idx - 1) / GROUP_SIZE) + 1
  rows[row][#rows[row] + 1] = volts
end

local function solve_groups_from_capture()
  local maximize = (math.random() < 0.5)
  groups = build_groups(rows, maximize)
  has_groups = true
  step_idx = 1
  print("hungary: solve mode = " .. (maximize and "max" or "min"))
end

local function as_braces(arr)
  local parts = {}
  for i = 1, #arr do
    parts[i] = tostring(arr[i])
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function print_groups(label, grouped)
  print(label)
  for i = 1, #grouped do
    print("group[" .. i .. "] = " .. as_braces(grouped[i]))
  end
end

local function clock_seconds()
  local beats = clock.get_beats
  if type(beats) == "function" then
    beats = beats()
  end

  local beat_sec = clock.get_beat_sec
  if type(beat_sec) == "function" then
    beat_sec = beat_sec()
  end

  if type(beats) == "number" and type(beat_sec) == "number" then
    return beats * beat_sec
  end
  return nil
end

local function on_gate_on()
  if not has_groups then
    return
  end

  local next_values = {}
  for i = 1, GROUP_SIZE do
    next_values[i] = groups[i][step_idx]
  end
  print(
    "hungary: gate ON step " .. tostring(step_idx)
      .. " -> out1=" .. tostring(next_values[1])
      .. " out2=" .. tostring(next_values[2])
      .. " out3=" .. tostring(next_values[3])
      .. " out4=" .. tostring(next_values[4])
  )
  emit_group_step()
end

local function on_gate_off()
  local now_sec = clock_seconds()
  if gate_on_seconds and now_sec then
    local elapsed = now_sec - gate_on_seconds
    print("hungary: gate held " .. tostring(elapsed) .. "s")
    if elapsed > HOLD_RESET_SECONDS then
      reset_learning_state("gate held high for " .. tostring(elapsed) .. "s")
      gate_on_seconds = nil
      return
    end
  end
  gate_on_seconds = nil

  if has_groups then
    return
  end

  local pitch = input[PITCH_INPUT].volts
  print("hungary: pitch in = " .. tostring(pitch))

  emit_all_outputs(pitch)
  capture_pitch(pitch)

  if #notes == BATCH_SIZE then
    print("hungary: captured 16 notes = " .. as_braces(notes))
    solve_groups_from_capture()
    print_groups("hungary: final groups", groups)
  end
end

function init()
  reset_learning_state("startup")
  gate_on_seconds = nil
  print("hungary: init")
  print("hungary: gate input = " .. GATE_INPUT .. ", pitch input = " .. PITCH_INPUT)
  print("hungary: gate threshold = " .. GATE_THRESHOLD .. "V, hysteresis = " .. GATE_HYSTERESIS .. "V")
  print("hungary: hold reset = " .. HOLD_RESET_SECONDS .. "s")

  -- Keep pitch input passive; we sample it at each gate trigger.
  input[PITCH_INPUT].mode("none")
  input[GATE_INPUT].change = function(state)
    local gate_volts = input[GATE_INPUT].volts
    local gate_high = (state == true) or (type(state) == "number" and state > 0)
    if type(state) ~= "boolean" and type(state) ~= "number" then
      gate_high = gate_volts > GATE_THRESHOLD
    end

    print("hungary: gate state=" .. tostring(state) .. " high=" .. tostring(gate_high) .. " in" .. GATE_INPUT .. "=" .. tostring(gate_volts))

    if gate_high then
      gate_on_seconds = clock_seconds()
      if gate_on_seconds then
        print("hungary: gate ON at " .. tostring(gate_on_seconds) .. "s")
      end
      on_gate_on()
    else
      on_gate_off()
    end
  end
  input[GATE_INPUT].mode("change", GATE_THRESHOLD, GATE_HYSTERESIS, "both")
  print("hungary: gate change mode armed (both)")

  -- If your cables are swapped, change GATE_INPUT/PITCH_INPUT above.
end
