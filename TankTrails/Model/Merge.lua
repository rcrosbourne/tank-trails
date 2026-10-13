local _, ns = ...
ns = ns or {}
local Util = ns.Util or require("Core.Util")

local Merge = {}
ns.Merge = Merge

-- Shipped record plus saved overlay, per spec §5.4. Saved wins per room key, per boss key and per route name.
function Merge.effective(shipped, saved, id, name)
  local d = shipped and Util.deepCopy(shipped) or { id = id, name = name }
  d.rooms, d.bosses, d.routes = d.rooms or {}, d.bosses or {}, d.routes or {}
  if not saved then return d end
  if saved.name then d.name = saved.name end
  if saved.art then d.art = Util.deepCopy(saved.art) end
  for k, v in pairs(saved.rooms or {}) do d.rooms[k] = Util.deepCopy(v) end
  for k, v in pairs(saved.bosses or {}) do d.bosses[k] = Util.deepCopy(v) end
  for _, r in ipairs(saved.routes or {}) do
    local replaced = false
    for i, s in ipairs(d.routes) do
      if s.name == r.name then d.routes[i] = Util.deepCopy(r); replaced = true; break end
    end
    if not replaced then table.insert(d.routes, Util.deepCopy(r)) end
  end
  d.activeRoute = saved.activeRoute
  return d
end

return Merge
