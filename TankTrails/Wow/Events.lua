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
  local self = setmetatable({ env = env, handlers = handlers, stats = {} }, Events)
  local frame = env.CreateFrame("Frame")
  for _, e in ipairs(Events.LIST) do frame:RegisterEvent(e) end
  local dispatch = function(event, ...) self:dispatch(event, ...) end
  if trap then dispatch = trap("event", dispatch) end
  frame:SetScript("OnEvent", function(_, event, ...) dispatch(event, ...) end)
  self.frame = frame
  return self
end

-- Reads a payload through Safe, counting the nil and secret ones under label for /tt debug.
function Events:field(raw, kind, label)
  local env = self.env
  local stat = self.stats[label]
  if not stat then
    stat = { nils = 0, secrets = 0 }
    self.stats[label] = stat
  end
  if env.issecretvalue and env.issecretvalue(raw) then
    stat.secrets = stat.secrets + 1
  elseif raw == nil then
    stat.nils = stat.nils + 1
  end
  return Safe[kind](env, raw)
end

function Events:statsLines()
  local lines = {}
  for label, st in pairs(self.stats) do
    if st.nils > 0 or st.secrets > 0 then
      lines[#lines + 1] = string.format("%s: %d nil, %d secret", label, st.nils, st.secrets)
    end
  end
  table.sort(lines)
  return lines
end

function Events:zoneText() return self:field(self.env.GetMinimapZoneText(), "string", "ZONE.text") end

-- The name of the current target when it exists, is not a player, and nothing about it is secret.
function Events:targetName()
  local env = self.env
  if not env.UnitExists("target") then return nil end
  local isPlayer = env.UnitIsPlayer("target")
  if env.issecretvalue and env.issecretvalue(isPlayer) then return nil end
  if isPlayer then return nil end
  return self:field(env.UnitName("target"), "string", "TARGET.name")
end

function Events:dispatch(event, ...)
  local h = self.handlers
  if event == "PLAYER_ENTERING_WORLD" then
    h.world()
  elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
    h.zone(self:zoneText(), event == "ZONE_CHANGED_NEW_AREA")
  elseif event == "ENCOUNTER_END" then
    local id, name, _, _, success = ...
    h.boss(self:field(id, "number", "ENCOUNTER_END.id"), self:field(name, "string", "ENCOUNTER_END.name"),
      self:field(success, "number", "ENCOUNTER_END.success") == 1)
  elseif event == "BOSS_KILL" then
    local id, name = ...
    h.boss(self:field(id, "number", "BOSS_KILL.id"), self:field(name, "string", "BOSS_KILL.name"), true)
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
