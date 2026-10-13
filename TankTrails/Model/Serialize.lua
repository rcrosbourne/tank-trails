local _, ns = ...
ns = ns or {}
local Util = ns.Util or require("Core.Util")

local Serialize = {}
ns.Serialize = Serialize

local FIELDS = { "id", "name", "art", "rooms", "bosses", "routes" }

local function roundPositions(t)
  for _, rec in pairs(t or {}) do
    if type(rec) == "table" then
      if type(rec.x) == "number" then rec.x = Util.round4(rec.x) end
      if type(rec.y) == "number" then rec.y = Util.round4(rec.y) end
    end
  end
end

-- Only the schema fields of spec §5.1, positions rounded to four decimals.
function Serialize.clean(d)
  local out = {}
  for _, f in ipairs(FIELDS) do out[f] = Util.deepCopy(d[f]) end
  roundPositions(out.rooms)
  roundPositions(out.bosses)
  return out
end

local function isIdent(k) return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil end

local function number(n)
  if n == math.floor(n) then return tostring(n) end
  return (string.format("%.4f", n):gsub("0+$", ""):gsub("%.$", ""))
end

local function write(out, v, indent)
  local t = type(v)
  if t == "string" then out[#out + 1] = string.format("%q", v)
  elseif t == "number" then out[#out + 1] = number(v)
  elseif t == "boolean" then out[#out + 1] = tostring(v)
  elseif t == "table" then
    if next(v) == nil then out[#out + 1] = "{}"; return end
    local pad = string.rep("  ", indent + 1)
    out[#out + 1] = "{\n"
    if Util.isArray(v) then
      for _, item in ipairs(v) do
        out[#out + 1] = pad
        write(out, item, indent + 1)
        out[#out + 1] = ",\n"
      end
    else
      for _, k in ipairs(Util.sortedKeys(v)) do
        out[#out + 1] = pad
        if isIdent(k) then out[#out + 1] = k
        elseif type(k) == "number" then out[#out + 1] = "[" .. number(k) .. "]"
        else out[#out + 1] = "[" .. string.format("%q", tostring(k)) .. "]" end
        out[#out + 1] = " = "
        write(out, v[k], indent + 1)
        out[#out + 1] = ",\n"
      end
    end
    out[#out + 1] = string.rep("  ", indent) .. "}"
  else
    error("cannot serialize a " .. t)
  end
end

function Serialize.dungeon(d)
  local out = { "TankTrails_RegisterDungeon(" }
  write(out, Serialize.clean(d), 0)
  out[#out + 1] = ")\n"
  return table.concat(out)
end

local function pos(rec, where)
  local hasPos = rec.x ~= nil or rec.y ~= nil
  for _, k in ipairs({ "x", "y" }) do
    local v = rec[k]
    if hasPos and v == nil then return false, where .. ": " .. k .. " is missing" end
    if v ~= nil and (type(v) ~= "number" or v ~= v or v < 0 or v > 1) then
      return false, where .. ": " .. k .. " must be between 0 and 1"
    end
  end
  if hasPos then
    local f = rec.floor
    if not (type(f) == "number" and f >= 1 and f % 1 == 0) then
      return false, where .. ": floor must be a positive whole number"
    end
  end
  return true
end

local BAD = { ["function"] = true, userdata = true, thread = true }

-- The type name of the first function, userdata or thread found anywhere in value; nil when none.
local function scan(value, seen)
  local t = type(value)
  if BAD[t] then return t end
  if t ~= "table" or seen[value] then return nil end
  seen[value] = true
  for k, v in pairs(value) do
    local bad = scan(k, seen) or scan(v, seen)
    if bad then return bad end
  end
  return nil
end

local function tableOrNil(d, key)
  if d[key] ~= nil and type(d[key]) ~= "table" then return false, key .. " must be a table" end
  return true
end

function Serialize.validate(d)
  if type(d) ~= "table" then return false, "not a table" end
  local bad = scan(d, {})
  if bad then return false, "import contains a " .. bad .. " value" end
  if type(d.id) ~= "number" then return false, "id must be a number" end
  if type(d.name) ~= "string" then return false, "name must be a string" end
  for _, key in ipairs({ "art", "rooms", "bosses", "routes" }) do
    local ok, err = tableOrNil(d, key)
    if not ok then return false, err end
  end
  for key, rec in pairs(d.rooms or {}) do
    if type(key) ~= "string" or type(rec) ~= "table" then return false, "rooms must map names to tables" end
    local ok, err = pos(rec, "room " .. key)
    if not ok then return false, err end
  end
  for key, rec in pairs(d.bosses or {}) do
    if type(key) ~= "string" or type(rec) ~= "table" then return false, "bosses must map names to tables" end
    local ok, err = pos(rec, "boss " .. key)
    if not ok then return false, err end
  end
  for i, route in ipairs(d.routes or {}) do
    if type(route) ~= "table" then return false, "route " .. i .. " must be a table" end
    if type(route.name) ~= "string" then return false, "route " .. i .. " has no route name" end
    local ok, err = tableOrNil(route, "steps")
    if not ok then return false, "route " .. route.name .. ": " .. err end
    for j, step in ipairs(route.steps or {}) do
      local where = "route " .. route.name .. " step " .. j
      if type(step) ~= "table" then return false, where .. " must be a table" end
      local n = (step.room and 1 or 0) + (step.boss and 1 or 0)
      if n ~= 1 then return false, where .. " needs exactly one of room or boss" end
      local target = step.room or step.boss
      if type(target) ~= "string" then return false, where .. ": room or boss must be a string" end
      if step.note ~= nil and type(step.note) ~= "string" then return false, where .. ": note must be a string" end
    end
  end
  return true
end

-- Runs the text under an environment holding only the register function (spec §5.5).
function Serialize.parse(text)
  if type(text) ~= "string" or Util.trim(text) == "" then return nil, "Nothing to import" end
  local fn, err = loadstring(text, "=import")
  if not fn then return nil, "Not valid Lua: " .. tostring(err) end
  local got, count = nil, 0
  setfenv(fn, { TankTrails_RegisterDungeon = function(d) count = count + 1; got = d end })
  local ok, perr = pcall(fn)
  if not ok then return nil, "Import failed: " .. tostring(perr) end
  if count ~= 1 then return nil, "Expected exactly one TankTrails_RegisterDungeon call, found " .. count end
  local vcall, vok, verr = pcall(Serialize.validate, got)
  if not vcall then return nil, "Import failed: " .. tostring(vok) end
  if not vok then return nil, verr end
  local cok, cleaned = pcall(Serialize.clean, got)
  if not cok then return nil, "Import failed: " .. tostring(cleaned) end
  return cleaned
end

return Serialize
