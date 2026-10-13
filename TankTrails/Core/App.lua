local _, ns = ...
ns = ns or {}
local function dep(name, path) return ns[name] or require(path) end
local Util = dep("Util", "Core.Util")
local Recorder = dep("Recorder", "Model.Recorder")
local Route = dep("Route", "Model.Route")
local Promote = dep("Promote", "Model.Promote")
local Serialize = dep("Serialize", "Model.Serialize")
local Geometry = dep("Geometry", "Model.Geometry")
local InstanceWatch = dep("InstanceWatch", "Wow.InstanceWatch")
local Events = dep("Events", "Wow.Events")

local App = {}
App.__index = App
ns.App = App
App.PREFIX = "|cff4fd18bTankTrails:|r "

function App.new(deps)
  local self = setmetatable({ deps = deps, env = deps.env, store = deps.store, errors = Util.newErrorLog() }, App)
  self.now = deps.now or function() return deps.env.time() end
  return self
end

function App:print(msg)
  local chat = self.env.DEFAULT_CHAT_FRAME
  if chat then chat:AddMessage(App.PREFIX .. tostring(msg)) end
end

function App:start()
  local function wrap(label, fn) return Util.wrap(self.errors, label, fn) end
  self.events = Events.create(self.env, {
    world = wrap("world", function() self:onWorld() end),
    zone = wrap("zone", function(text, newArea) self:onZone(text, newArea) end),
    boss = wrap("boss", function(id, name, ok) self:onBoss(id, name, ok) end),
    combatStart = wrap("combatStart", function() self:onCombat(true) end),
    combatEnd = wrap("combatEnd", function() self:onCombat(false) end),
    dead = wrap("dead", function() self:onDead() end),
    target = wrap("target", function(name) self:onTarget(name) end),
  }, wrap)
  local ui = self.deps.ui
  if ui and ui.hud then
    self.hud = ui.hud(self.store:settings().hud, function() self:toggleMap() end)
  end
  self.ticker = self.env.C_Timer.NewTicker(1, wrap("tick", function() self:onTick() end))
  wrap("start", function() self:onWorld() end)()
  return true
end

-- The map arrives in the next plan; keep the hook so the HUD click has somewhere to go.
function App:toggleMap()
  if self.deps.ui and self.deps.ui.toggleMap then self.deps.ui.toggleMap() else self:print("The map is not built yet.") end
end

-- Spec §6.1
function App:onWorld()
  local id, name = InstanceWatch.current(self.env)
  if not id and InstanceWatch.pending(self.env) then return end
  local saved = self.store:run()
  if id then
    local run, stale = Recorder.open(saved, id, name, self.now())
    if stale then
      self.store:fileRun(stale)
      self.last = { id = stale.dungeon, name = stale.name }
      self.store:setLast(stale.dungeon, stale.name)
    end
    self.store:setRun(run)
    self.run, self.dungeon, self.away = run, self.store:effective(id, name), false
    self:onZone(self.events:zoneText(), false)
  elseif saved and not saved.endedAt then
    if Recorder.leave(saved, self.now()) then
      self:print("Left " .. tostring(saved.name) .. ". Re-enter within 30 minutes to continue the run, or /tt promote it now.")
    end
    self.run, self.away = saved, true
    self.dungeon = self.dungeon or self.store:effective(saved.dungeon, saved.name)
  else
    self.run, self.dungeon, self.away = nil, nil, false
  end
  self:refresh()
end

function App:onZone(text, newArea)
  if not self.run then
    if newArea then self:onWorld() end
    return
  end
  if self.away then
    if newArea or InstanceWatch.current(self.env) then self:onWorld() end
    return
  end
  if newArea and not InstanceWatch.pending(self.env) and InstanceWatch.current(self.env) ~= self.run.dungeon then return self:onWorld() end
  local ev = Recorder.room(self.run, text, self.now())
  if ev then self.store:seenRoom(self.run.dungeon, ev.room, self.now()) end
  self:refresh()
end

function App:file(run)
  Recorder.close(run, self.now())
  self.store:fileRun(run)
  self.store:setRun(nil)
  self.last = { id = run.dungeon, name = run.name }
  self.store:setLast(run.dungeon, run.name)
end

function App:onTick()
  local now = self.now()
  if self.run and Recorder.expired(self.run, now) then
    local run = self.run
    self:file(run)
    self:print("Run in " .. tostring(run.name) .. " recorded. /tt promote turns it into a route.")
    self.run, self.dungeon, self.away = nil, nil, false
    self:refresh()
    return
  end
  if not self.run or self.away then
    if InstanceWatch.current(self.env) then self:onWorld() end
    return
  end
  self:onZone(self.events:zoneText(), false)
end

local function bossKey(ev) return ev.name or ("#" .. tostring(ev.encounterID)) end

function App:onBoss(id, name, success)
  if not self.run or not success then return end
  local ev = Recorder.boss(self.run, name, id, self.now())
  if not ev then return end
  self.store:learnBoss(self.run.dungeon, bossKey(ev), { room = ev.room, encounterID = ev.encounterID })
  self.dungeon = self.store:effective(self.run.dungeon, self.run.name)
  self:refresh()
end

function App:onCombat(started)
  self.inCombat = started
  if not self.run then return end
  if started then Recorder.pullStart(self.run, self.now()) else Recorder.pullEnd(self.run, self.now()) end
end

function App:onDead() if self.run then Recorder.death(self.run) end end
-- Target names are only read out of combat (spec §6.4).
function App:onTarget(name)
  if self.run and not self.inCombat then Recorder.target(self.run, name, self.now()) end
end

-- Where a step sits on the map: a room's own position; a boss's own, else its room's (spec §5.1).
local function position(d, step)
  if step.room then
    local r = d.rooms[step.room]
    return r and r.x and r or nil
  end
  local b = d.bosses[step.boss]
  if b and b.x then return b end
  local r = b and b.room and d.rooms[b.room]
  return r and r.x and r or nil
end

function App:view()
  local run, d = self.run, self.dungeon
  if not run or not d or self.away then return { mode = "none" } end
  local v = { dungeonName = d.name, currentRoom = Recorder.currentRoom(run), runSeconds = self.now() - run.startedAt }
  local route = Route.select(d, d.activeRoute, run.events)
  self.route = route
  if not route then
    v.mode, v.counts, self.state = "learning", Recorder.counts(run), nil
    return v
  end
  local state = Route.fold(route, run.events, d.bosses)
  self.state = state
  v.mode, v.routeName, v.offRoute, v.unexpected = "route", route.name, state.offRoute, state.unexpected
  v.done, v.total = Route.progress(route, state)
  local cur = route.steps[state.cursor]
  v.note = cur and cur.note or nil
  local j = Route.next(route, state)
  if not j then v.complete = true; return v end
  local nxt = route.steps[j]
  v.next, v.nextKind, v.nextNote = nxt.room or nxt.boss, nxt.room and "room" or "boss", nxt.note
  local a = v.currentRoom and d.rooms[v.currentRoom]
  local b = position(d, nxt)
  if a and a.x and b then
    if a.floor == b.floor then
      v.bearing = Geometry.bearing(a, b)
    else
      v.floorHint = b.floor > a.floor and "up" or "down"
      local floors = d.art and d.art.floors
      v.floorName = floors and floors[b.floor] and floors[b.floor].name or ("floor " .. tostring(b.floor))
    end
  end
  return v
end

function App:refresh()
  local view = self:view()
  if self.hud then self.hud:update(view) end
  return view
end

-- The dungeon commands act on: the one the player is in, else the one they last left this session.
function App:context()
  if self.run then return self.run.dungeon, self.run.name, self.run end
  local last = self.last or self.store:last()
  if last then return last.id, last.name, self.store:lastRun(last.id) end
  return nil
end

function App:note(text)
  if not self.run or self.away then return false, "Not in a dungeon." end
  local view = self:view()
  if view.mode == "learning" then
    if Util.trim(text) == "" then return false, "Note text is empty." end
    Recorder.note(self.run, Util.trim(text), self.now())
    return true, "Note saved for " .. tostring(view.currentRoom) .. "."
  end
  if self.state.cursor == 0 then return false, "No current step yet." end
  self.store:setNote(self.run.dungeon, self.route.name, self.state.cursor, text)
  self.dungeon = self.store:effective(self.run.dungeon, self.run.name)
  self:refresh()
  return true, "Note saved on step " .. self.state.cursor .. "."
end

function App:tickBoss(name)
  if not self.run or self.away then return false, "Not in a dungeon." end
  local view = self:view()
  if not name then
    if view.mode ~= "route" then return false, "No route here. Give the boss a name: /tt boss <name>." end
    local steps, state = self.route.steps, self.state
    for _, start in ipairs({ state.cursor + 1, 1 }) do
      for j = start, #steps do
        if steps[j].boss and not state.done[j] then name = steps[j].boss; break end
      end
      if name then break end
    end
    if not name then return false, "Every boss in the route is done." end
  end
  local ev = Recorder.boss(self.run, name, nil, self.now(), true)
  if not ev then return false, "That boss was just recorded." end
  self.store:learnBoss(self.run.dungeon, name, { room = ev.room })
  self.dungeon = self.store:effective(self.run.dungeon, self.run.name)
  self:refresh()
  return true, "Ticked " .. name .. "."
end

function App:promote(name, force)
  local id, dname, run = self:context()
  if not run then return false, "Enter a dungeon, or finish a run, first." end
  local d = self.store:effective(id, dname)
  local today = self.env.date("%Y-%m-%d", self.now())
  name = name and Util.trim(name) ~= "" and Util.trim(name) or nil
  local target = name or ("Recorded " .. today)
  local old
  for _, r in ipairs(d.routes) do
    if r.name == target then old = r end
  end
  if old and not force then return "confirm" end
  local route, info, err = Promote.run(run, old, target, today, self.now())
  if not route then return false, err end
  self.store:setRoute(id, route)
  for key, rec in pairs(info) do self.store:learnBoss(id, key, rec) end
  if self.run then self.dungeon = self.store:effective(id, dname) end
  self:refresh()
  return true, "Route '" .. route.name .. "' saved with " .. #route.steps .. " steps and set active."
end

function App:switchRoute(name)
  local id, dname = self:context()
  if not id then return false, "Not in a dungeon." end
  local d = self.store:effective(id, dname)
  local names = {}
  for _, r in ipairs(d.routes) do
    names[#names + 1] = r.name
    if r.name == name then
      self.store:setActiveRoute(id, name)
      if self.run then self.dungeon = self.store:effective(id, dname) end
      self:refresh()
      return true, "Active route: " .. name .. "."
    end
  end
  return false, "No route '" .. tostring(name) .. "'. Routes: " .. (#names > 0 and table.concat(names, ", ") or "none") .. "."
end

function App:exportText()
  local id, dname = self:context()
  if not id then return nil, "Not in a dungeon." end
  return Serialize.dungeon(self.store:effective(id, dname))
end

-- Parses first; without force it only reports the dungeon's name so the caller can confirm (spec §5.5).
function App:importText(text, force)
  local d, err = Serialize.parse(text)
  if not d then return false, err end
  if not force then return "confirm", d.name end
  self.store:replaceOverlay(d.id, d)
  if self.run and self.run.dungeon == d.id then
    self.dungeon = self.store:effective(d.id, self.run.name)
    self:refresh()
  end
  return true, "Imported " .. d.name .. " (" .. #(d.routes or {}) .. " routes)."
end

function App:reset(force)
  local id, dname = self:context()
  if not id then return false, "Not in a dungeon." end
  if not force then return "confirm" end
  self.store:reset(id)
  if self.run then self.dungeon = self.store:effective(id, dname) end
  self:refresh()
  return true, "Saved data for " .. tostring(dname) .. " wiped."
end

function App:debugLines()
  local lines = {}
  local id, dname = self:context()
  lines[#lines + 1] = id and ("dungeon " .. id .. " " .. tostring(dname)) or "no dungeon"
  lines[#lines + 1] = "zone text: " .. tostring(self.events and self.events:zoneText())
  if self.run then
    local v = self:view()
    lines[#lines + 1] = "mode " .. v.mode .. (v.routeName and (", route " .. v.routeName) or "") ..
      (self.state and (", cursor " .. self.state.cursor) or "")
    local n = #self.run.events
    for i = math.max(1, n - 9), n do
      local ev = self.run.events[i]
      lines[#lines + 1] = string.format("%6.1f %s %s", ev.t, ev.kind, tostring(ev.room or ev.name or ev.text or ""))
    end
  end
  local stats = self.events and self.events:statsLines() or {}
  if #stats == 0 then lines[#lines + 1] = "payloads: all readable" end
  for _, l in ipairs(stats) do lines[#lines + 1] = l end
  lines[#lines + 1] = "errors: " .. #self.errors.entries
  return lines
end

function App:setAutoOpen(on) self.store:settings().autoOpen = on and true or false end

function App:setScale(n)
  self.store:settings().hud.scale = n
  if self.hud then self.hud:setScale(n) end
end

function App:toggleHud()
  if not self.hud then return end
  self.hud:toggle()
  self.store:settings().hud.shown = self.hud.shown
  self:refresh()
end

function App:lockHud()
  local hud = self.store:settings().hud
  hud.locked = not hud.locked
  if self.hud then self.hud:setLocked(hud.locked) end
  return hud.locked
end

return App
