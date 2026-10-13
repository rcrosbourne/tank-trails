local _, ns = ...
ns = ns or {}
local Util = ns.Util or require("Core.Util")
local Merge = ns.Merge or require("Model.Merge")

local Store = {}
Store.__index = Store
ns.Store = Store
Store.MAX_RUNS = 5

function Store.new(accountDb, charDb, shipped)
  return setmetatable({ account = accountDb, char = charDb, shipped = shipped or {} }, Store)
end

function Store:settings() return self.account.settings end

function Store:overlay(id)
  local all = self.account.dungeons
  all[id] = all[id] or {}
  return all[id]
end

function Store:effective(id, name)
  return Merge.effective(self.shipped[id], self.account.dungeons[id], id, name)
end

function Store:run() return self.char.run end
function Store:setRun(run) self.char.run = run end

function Store:fileRun(run)
  local runs = self.account.runs
  runs[run.dungeon] = runs[run.dungeon] or {}
  table.insert(runs[run.dungeon], 1, run)
  while #runs[run.dungeon] > Store.MAX_RUNS do table.remove(runs[run.dungeon]) end
end

function Store:lastRun(id)
  local runs = self.account.runs[id]
  return runs and runs[1] or nil
end

local function shippedRecord(self, id, field, key)
  local d = self.shipped[id]
  return d and d[field] and d[field][key] or nil
end

-- The overlay's own record for a room or boss, seeded from shipped when it has one.
local function ownRecord(self, id, field, key)
  local o = self:overlay(id)
  o[field] = o[field] or {}
  if not o[field][key] then o[field][key] = Util.deepCopy(shippedRecord(self, id, field, key)) or {} end
  return o[field][key]
end

function Store:seenRoom(id, key, now)
  local o = self:overlay(id)
  o.rooms = o.rooms or {}
  if shippedRecord(self, id, "rooms", key) then return end
  if not o.rooms[key] then o.rooms[key] = { seenAt = now } end
end

local function place(rec, floor, x, y)
  rec.floor, rec.x, rec.y = floor, Util.round4(x), Util.round4(y)
end

function Store:placeRoom(id, key, floor, x, y) place(ownRecord(self, id, "rooms", key), floor, x, y) end
function Store:placeBoss(id, key, floor, x, y) place(ownRecord(self, id, "bosses", key), floor, x, y) end

function Store:learnBoss(id, key, info)
  local rec = ownRecord(self, id, "bosses", key)
  if info.room then rec.room = info.room end
  if info.encounterID then rec.encounterID = info.encounterID end
end

local function routeIndex(routes, name)
  for i, r in ipairs(routes) do
    if r.name == name then return i end
  end
  return nil
end

function Store:setRoute(id, route)
  local o = self:overlay(id)
  o.routes = o.routes or {}
  local i = routeIndex(o.routes, route.name)
  if i then o.routes[i] = route else table.insert(o.routes, route) end
  o.activeRoute = route.name
end

function Store:setActiveRoute(id, name) self:overlay(id).activeRoute = name end

-- The overlay's copy of a route, copied from shipped on first edit; nil when no such route exists.
function Store:editableRoute(id, name)
  local o = self:overlay(id)
  o.routes = o.routes or {}
  local i = routeIndex(o.routes, name)
  if i then return o.routes[i] end
  local d = self.shipped[id]
  local j = d and d.routes and routeIndex(d.routes, name)
  if not j then return nil end
  local copy = Util.deepCopy(d.routes[j])
  table.insert(o.routes, copy)
  return copy
end

function Store:setNote(id, routeName, index, text)
  local route = self:editableRoute(id, routeName)
  local step = route and route.steps[index]
  if not step then return false end
  text = Util.trim(text)
  step.note = text ~= "" and text or nil
  return true
end

-- Import: the overlay becomes the imported record; its first route becomes active.
function Store:replaceOverlay(id, dungeon)
  local o = { name = dungeon.name, art = dungeon.art, rooms = dungeon.rooms or {}, bosses = dungeon.bosses or {},
              routes = dungeon.routes or {} }
  o.activeRoute = o.routes[1] and o.routes[1].name or nil
  self.account.dungeons[id] = o
end

function Store:reset(id) self.account.dungeons[id] = nil end

return Store
