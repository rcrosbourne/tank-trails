local _, ns = ...
ns = ns or {}
local Safe = ns.Safe or require("Wow.Safe")

local Events = {}
Events.__index = Events
ns.Events = Events

Events.LIST = {
  "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
  "ENCOUNTER_END", "BOSS_KILL", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD",
  "PLAYER_TARGET_CHANGED",
}

function Events.create(env, handlers, trap)
  local self = setmetatable({ env = env, handlers = handlers }, Events)
  local frame = env.CreateFrame("Frame")
  for _, e in ipairs(Events.LIST) do frame:RegisterEvent(e) end
  local dispatch = function(event, ...) self:dispatch(event, ...) end
  if trap then dispatch = trap("event", dispatch) end
  frame:SetScript("OnEvent", function(_, event, ...) dispatch(event, ...) end)
  self.frame = frame
  return self
end

function Events:zoneText() return Safe.string(self.env, self.env.GetMinimapZoneText()) end

-- The name of the current target when it exists, is not a player, and nothing about it is secret.
function Events:targetName()
  local env = self.env
  if not env.UnitExists("target") then return nil end
  local isPlayer = env.UnitIsPlayer("target")
  if env.issecretvalue and env.issecretvalue(isPlayer) then return nil end
  if isPlayer then return nil end
  return Safe.string(env, env.UnitName("target"))
end

function Events:dispatch(event, ...)
  local h, env = self.handlers, self.env
  if event == "PLAYER_ENTERING_WORLD" then
    h.world()
  elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
    h.zone(self:zoneText(), event == "ZONE_CHANGED_NEW_AREA")
  elseif event == "ENCOUNTER_END" then
    local id, name, _, _, success = ...
    h.boss(Safe.number(env, id), Safe.string(env, name), Safe.number(env, success) == 1)
  elseif event == "BOSS_KILL" then
    local id, name = ...
    h.boss(Safe.number(env, id), Safe.string(env, name), true)
  elseif event == "PLAYER_REGEN_DISABLED" then
    h.combatStart()
  elseif event == "PLAYER_REGEN_ENABLED" then
    h.combatEnd()
  elseif event == "PLAYER_DEAD" then
    h.dead()
  elseif event == "PLAYER_TARGET_CHANGED" then
    h.target(self:targetName())
  end
end

function Events:stop() self.frame:UnregisterAllEvents() end

return Events
