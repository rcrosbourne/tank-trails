local _, ns = ...
ns = ns or {}

local Safe = {}
ns.Safe = Safe

-- nil for any value the client marks secret (Midnight secret values, spec §3); the value otherwise.
function Safe.value(env, v)
  local check = env.issecretvalue
  if check and check(v) then return nil end
  return v
end

function Safe.string(env, v)
  v = Safe.value(env, v)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

function Safe.number(env, v)
  v = Safe.value(env, v)
  if type(v) == "number" then return v end
  return nil
end

return Safe
