local _, ns = ...
ns = ns or {}

local Util = {}
ns.Util = Util
Util.MAX_ERRORS = 50

function Util.newErrorLog(max)
  local log = { entries = {}, max = max or Util.MAX_ERRORS }
  function log:add(label, err)
    table.insert(self.entries, { label = label, message = tostring(err) })
    while #self.entries > self.max do table.remove(self.entries, 1) end
  end
  function log:clear() self.entries = {} end
  return log
end

local function pack(...) return { n = select("#", ...), ... } end

-- Calls fn(...); on error, records it under label and returns nothing.
function Util.safeCall(log, label, fn, ...)
  local results = pack(pcall(fn, ...))
  if not results[1] then
    log:add(label, results[2])
    return
  end
  return unpack(results, 2, results.n)
end

function Util.wrap(log, label, fn)
  return function(...) return Util.safeCall(log, label, fn, ...) end
end

function Util.round4(n) return math.floor(n * 10000 + 0.5) / 10000 end
function Util.round1(n) return math.floor(n * 10 + 0.5) / 10 end

function Util.sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

function Util.deepCopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Util.deepCopy(v) end
  return out
end

function Util.trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- A non-empty table whose keys are exactly 1..n.
function Util.isArray(t)
  local n = #t
  if n == 0 then return false end
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
  end
  return true
end

return Util
