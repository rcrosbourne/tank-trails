local _, ns = ...
ns = ns or {}

TankTrails = TankTrails or {}
TankTrails.shipped = TankTrails.shipped or {}

-- Data/Dungeons/*.lua call this while the addon loads (spec §5.1).
function TankTrails_RegisterDungeon(d)
  if type(d) ~= "table" or type(d.id) ~= "number" then return false end
  TankTrails.shipped[d.id] = d
  return true
end

local Init = {}
ns.Init = Init

Init.ACCOUNT_DEFAULTS = {
  dungeons = {},
  runs = {},
  settings = {
    autoOpen = true,
    hud = { scale = 1, locked = false, shown = true },
    map = {},
  },
}

Init.CHAR_DEFAULTS = {}

-- Fills missing keys from defaults, recursively, without overwriting existing values.
function Init.applyDefaults(target, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then target[key] = {} end
      Init.applyDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
  return target
end

return Init
