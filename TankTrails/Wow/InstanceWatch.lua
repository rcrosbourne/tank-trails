local _, ns = ...
ns = ns or {}
local Safe = ns.Safe or require("Wow.Safe")

local InstanceWatch = {}
ns.InstanceWatch = InstanceWatch

-- The party dungeon the player is in: instanceMapID and name (spec §6.1). nil anywhere else, and nil
-- while GetInstanceInfo has no data yet during a loading screen.
function InstanceWatch.current(env)
  local inInstance, kind = env.IsInInstance()
  if not inInstance or kind ~= "party" then return nil end
  local name, _, _, _, _, _, _, id = env.GetInstanceInfo()
  name = Safe.string(env, name)
  id = Safe.number(env, id)
  if not name or not id then return nil end
  return id, name
end

return InstanceWatch
