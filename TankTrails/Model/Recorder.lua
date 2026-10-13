local _, ns = ...
ns = ns or {}
local Util = ns.Util or require("Core.Util")

local Recorder = {}
ns.Recorder = Recorder

Recorder.BOSS_WINDOW = 5     -- seconds: two boss events with one identity are one kill (spec §6.3)
Recorder.GRACE = 1800        -- seconds a run stays resumable after the player leaves its dungeon (spec §6.1)
Recorder.TARGET_WINDOW = 10  -- seconds: a pull takes the last out-of-combat target this recent (spec §6.4)

local function stamp(run, now) return Util.round1(now - run.startedAt) end

-- Same boss when both carry an encounter id (ids must match); otherwise a non-nil name must match.
local function sameBoss(last, encounterID, name)
  if last.id and encounterID then return last.id == encounterID end
  return name ~= nil and last.name == name
end

local function push(run, ev)
  table.insert(run.events, ev)
  return ev
end

-- Resume saved when it is this dungeon's unfinished run; otherwise start fresh and hand back the
-- unfinished one, ended, for filing (spec §6.1).
function Recorder.open(saved, id, name, now)
  if saved and saved.dungeon == id and not saved.endedAt then
    saved.leftAt = nil
    return saved, nil
  end
  local stale
  if saved and not saved.endedAt then
    saved.endedAt = now
    stale = saved
  end
  return { dungeon = id, name = name, startedAt = now, events = {} }, stale
end

-- Marks the run as away; true only the first time.
function Recorder.leave(run, now)
  if run.leftAt then return false end
  run.leftAt = now
  return true
end

function Recorder.expired(run, now)
  return run.leftAt ~= nil and now - run.leftAt >= Recorder.GRACE
end

function Recorder.close(run, now)
  Recorder.pullEnd(run, now)
  run.endedAt = now
end

function Recorder.room(run, text, now)
  if type(text) ~= "string" or text == "" or text == run.lastRoom then return nil end
  run.lastRoom = text
  return push(run, { t = stamp(run, now), kind = "room", room = text })
end

function Recorder.currentRoom(run) return run.lastRoom end

function Recorder.target(run, name, now)
  if name then run.lastTarget = { name = name, at = now } else run.lastTarget = nil end
end

function Recorder.pullStart(run, now)
  if run.pull then return nil end
  local ev = { t = stamp(run, now), kind = "pull", room = run.lastRoom, deaths = 0 }
  local target = run.lastTarget
  if target and now - target.at <= Recorder.TARGET_WINDOW then ev.target = target.name end
  run.pull = ev
  return push(run, ev)
end

function Recorder.pullEnd(run, now)
  local pull = run.pull
  if not pull then return nil end
  pull.duration = Util.round1(now - (run.startedAt + pull.t))
  run.pull = nil
  return pull
end

function Recorder.death(run)
  if not run.pull then return false end
  run.pull.deaths = run.pull.deaths + 1
  return true
end

function Recorder.boss(run, name, encounterID, now, manual)
  local key = encounterID or name
  if key == nil then return nil end
  local last = run.lastBoss
  if last and now - last.at <= Recorder.BOSS_WINDOW and sameBoss(last, encounterID, name) then
    return nil
  end
  run.lastBoss = { id = encounterID, name = name, at = now }
  local ev = { t = stamp(run, now), kind = "boss", name = name, encounterID = encounterID, room = run.lastRoom }
  if manual then ev.manual = true end
  return push(run, ev)
end

function Recorder.note(run, text, now)
  return push(run, { t = stamp(run, now), kind = "note", room = run.lastRoom, text = text })
end

function Recorder.counts(run)
  local rooms, bosses = {}, 0
  for _, ev in ipairs(run.events) do
    if ev.kind == "room" then rooms[ev.room] = true elseif ev.kind == "boss" then bosses = bosses + 1 end
  end
  local n = 0
  for _ in pairs(rooms) do n = n + 1 end
  return { rooms = n, bosses = bosses }
end

return Recorder
