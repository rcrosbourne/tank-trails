local _, ns = ...
ns = ns or {}

local Promote = {}
ns.Promote = Promote
Promote.FLAP = 15  -- seconds (spec §6.8 step 2)

local function bossKey(ev) return ev.name or ("#" .. tostring(ev.encounterID)) end

-- Room events with how long each stay lasted; the last stay ends at endedAt or now.
local function stays(run, now)
  local endT = (run.endedAt or now) - run.startedAt
  local rooms = {}
  for _, ev in ipairs(run.events) do
    if ev.kind == "room" then rooms[#rooms + 1] = { room = ev.room, t = ev.t } end
  end
  for i, r in ipairs(rooms) do
    local nextT = rooms[i + 1] and rooms[i + 1].t or endT
    r.stay = math.max(0, nextT - r.t)
  end
  return rooms
end

-- A, B, A with a short B is a flap: drop B and fold both A stays together. Then merge A, A.
local function collapse(rooms)
  local changed = true
  while changed do
    changed = false
    for i = 2, #rooms - 1 do
      if rooms[i - 1].room == rooms[i + 1].room and rooms[i].stay < Promote.FLAP then
        rooms[i - 1].stay = rooms[i - 1].stay + rooms[i].stay + rooms[i + 1].stay
        table.remove(rooms, i + 1)
        table.remove(rooms, i)
        changed = true
        break
      end
    end
  end
  local out = {}
  for _, r in ipairs(rooms) do
    local last = out[#out]
    if last and last.room == r.room then last.stay = last.stay + r.stay else out[#out + 1] = r end
  end
  return out
end

-- Index of the last room entered at or before t; 0 when t is before the first room.
local function roomIndexAt(rooms, t)
  local idx = 0
  for i, r in ipairs(rooms) do
    if r.t <= t then idx = i else break end
  end
  return idx
end

function Promote.run(run, oldRoute, name, today, now)
  local rooms = collapse(stays(run, now))
  local bosses, notes = {}, {}
  for _, ev in ipairs(run.events) do
    if ev.kind == "boss" and (ev.name or ev.encounterID) then
      bosses[#bosses + 1] = ev
    elseif ev.kind == "note" and ev.room and notes[ev.room] == nil then
      notes[ev.room] = ev.text
    end
  end
  if #rooms == 0 and #bosses == 0 then return nil, nil, "Nothing recorded in this run" end

  local byRoom = {}
  for _, b in ipairs(bosses) do
    local i = roomIndexAt(rooms, b.t)
    byRoom[i] = byRoom[i] or {}
    table.insert(byRoom[i], b)
  end

  local steps = {}
  local function addBosses(i)
    for _, b in ipairs(byRoom[i] or {}) do steps[#steps + 1] = { boss = bossKey(b) } end
  end
  addBosses(0)
  local noted = {}
  for i, r in ipairs(rooms) do
    local step = { room = r.room }
    if notes[r.room] and not noted[r.room] then step.note, noted[r.room] = notes[r.room], true end
    steps[#steps + 1] = step
    addBosses(i)
  end

  if oldRoute then
    local used = {}
    for _, s in ipairs(steps) do
      for j, o in ipairs(oldRoute.steps or {}) do
        if not used[j] and ((s.room and o.room == s.room) or (s.boss and o.boss == s.boss)) then
          used[j] = true
          if not s.note then s.note = o.note end
          break
        end
      end
    end
  end

  local info = {}
  for _, b in ipairs(bosses) do info[bossKey(b)] = { room = b.room, encounterID = b.encounterID } end
  return { name = name or ("Recorded " .. today), steps = steps }, info
end

return Promote
