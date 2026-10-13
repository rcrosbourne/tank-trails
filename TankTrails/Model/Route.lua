local _, ns = ...
ns = ns or {}

local Route = {}
ns.Route = Route

-- Encounter id when both the event and the dungeon's boss record have one, else the name (spec §6.3).
function Route.bossMatches(step, ev, bosses)
  if not step.boss then return false end
  local info = bosses and bosses[step.boss]
  if ev.encounterID and info and info.encounterID then return ev.encounterID == info.encounterID end
  return ev.name ~= nil and ev.name == step.boss
end

function Route.newState() return { cursor = 0, done = {}, offRoute = nil, unexpected = {} } end

-- One event against the route, per spec §6.5.
function Route.apply(route, state, ev, bosses)
  local steps = route.steps
  if ev.kind == "room" then
    for i = state.cursor + 1, #steps do
      if steps[i].room == ev.room then state.cursor, state.offRoute = i, nil; return state end
    end
    for i = state.cursor, 1, -1 do
      if steps[i].room == ev.room then state.cursor, state.offRoute = i, nil; return state end
    end
    state.offRoute = ev.room
  elseif ev.kind == "boss" then
    for i = state.cursor + 1, #steps do
      if Route.bossMatches(steps[i], ev, bosses) then state.done[i] = true; state.cursor = i; return state end
    end
    for i = 1, #steps do
      if Route.bossMatches(steps[i], ev, bosses) then state.done[i] = true; state.cursor = i; return state end
    end
    table.insert(state.unexpected, ev.name or ("#" .. tostring(ev.encounterID)))
  end
  return state
end

function Route.fold(route, events, bosses)
  local state = Route.newState()
  for _, ev in ipairs(events or {}) do Route.apply(route, state, ev, bosses) end
  return state
end

-- First step after the cursor that is not a done boss; nil when the route is complete.
function Route.next(route, state)
  for j = state.cursor + 1, #route.steps do
    local s = route.steps[j]
    if not (s.boss and state.done[j]) then return j end
  end
  return nil
end

function Route.progress(route, state)
  local done, total = 0, 0
  for i, s in ipairs(route.steps) do
    if s.boss then
      total = total + 1
      if state.done[i] then done = done + 1 end
    end
  end
  return done, total
end

local function hasRoom(route, room)
  for _, s in ipairs(route.steps) do
    if s.room == room then return true end
  end
  return false
end

local function byName(routes, name)
  for _, r in ipairs(routes) do
    if r.name == name then return r end
  end
  return nil
end

-- The route a run follows (spec §6.6): the active one or the first; until the first boss kill, a room
-- that is in no step of the current route but in another route's step switches to that route.
function Route.select(dungeon, activeName, events)
  local routes = dungeon.routes or {}
  if #routes == 0 then return nil end
  local route = (activeName and byName(routes, activeName)) or routes[1]
  for _, ev in ipairs(events or {}) do
    if ev.kind == "boss" then break end
    if ev.kind == "room" and not hasRoom(route, ev.room) then
      for _, other in ipairs(routes) do
        if other ~= route and hasRoom(other, ev.room) then route = other; break end
      end
    end
  end
  return route
end

return Route
