# TankTrails Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first shippable TankTrails: a recorder that logs rooms, pulls and boss kills inside a Forever dungeon, a route cursor, a four-line HUD, promotion of a run into a route, and export/import, so beta runs produce data before 2026-10-21.

**Architecture:** Pure-Lua Model modules (Recorder, Route, Merge, Promote, Serialize, Geometry) take plain tables and are tested under busted. Thin Wow adapters (Safe, InstanceWatch, Events, Store) take an `env` table so tests inject fakes. `Core/App` folds the run's events over the active route on every change and hands a view table to `UI/Hud`. `Core/Commands` exposes `/tt`.

**Tech Stack:** WoW addon Lua 5.1 (interface 16001, Forever flavor), busted 2.x on a hererocks Lua 5.1.5 in `.lua/`, no libraries.

**Spec:** `docs/superpowers/specs/2026-10-12-tanktrails-design.md`. This plan covers spec §2 build-order phase 1 (recorder, storage, HUD, promote, export). The map (spec §7.2–7.4) and starter data (spec §12) are separate plans written after this one ships.

## Global Constraints

- TOC: `## Interface: 16001`, `## SavedVariables: TankTrailsDB`, `## SavedVariablesPerCharacter: TankTrailsCharDB` (spec §11).
- Lua 5.1 only: `unpack` not `table.unpack`, `loadstring` and `setfenv` exist, no `goto`, no integer division, `#` on sequences only.
- No libraries: no Ace, no LibStub, no HereBeDragons (spec §2).
- Every module starts `local _, ns = ...` / `ns = ns or {}`, publishes itself on `ns`, resolves dependencies with `ns[name] or require(path)`, and ends with `return Module`, so it loads in game and under busted.
- Game calls live only in `Wow/*`, `UI/*`, `Core/Boot.lua` and `Core/Commands.lua`. `Model/*` never touches a global.
- Dungeon identity is `instanceMapID` (8th return of `GetInstanceInfo`); room identity is `GetMinimapZoneText` verbatim (spec §2).
- Timings: boss de-duplication 5 s, pre-pull target window 10 s, flap collapse under 15 s, ticker 1 s (spec §6).
- Caps: 5 recent runs per dungeon, 50 error-log entries. Positions stored to four decimals (spec §5).
- Slash prefix `/tt`; chat prefix `|cff4fd18bTankTrails:|r`.
- Every secret-capable payload passes through `Wow/Safe` before reaching the Model (spec §8).

## Review Focus

1. `GetInstanceInfo` returns a nil name or id on `PLAYER_ENTERING_WORLD` during the loading screen: no run must open, and the next zone event must retry. Pinned in Task 12 (`opens the run on the first event that has instance info`).
2. A boss event whose name is secret and that carries no encounter id: it must be dropped silently, not logged as a boss named `nil`. Pinned in Task 4 (`ignores a boss with no identity`).
3. `/tt promote` on a run with no room and no boss events: refuse with a message rather than save an empty route. Pinned in Task 7 (`refuses an empty run`).
4. Imported text that calls anything outside the register function, for example `print(1)`: the sandbox must reject it with the error message and leave saved data untouched. Pinned in Task 8 (`rejects text that calls a global`).
5. The saved `activeRoute` names a route that no longer exists (renamed or reset): selection must fall back to the first route instead of leaving the HUD in learning mode. Pinned in Task 5 (`falls back to the first route when activeRoute is missing`).

## File Structure

```
TankTrails/TankTrails.toc          load order; SavedVariables names
TankTrails/Core/Init.lua           TankTrails_RegisterDungeon, SavedVariables defaults, applyDefaults
TankTrails/Core/Util.lua           error log, safeCall/wrap, round4, sortedKeys, deepCopy, trim
TankTrails/Core/App.lua            run lifecycle, event handlers, replay, view table, actions
TankTrails/Core/Commands.lua       /tt parsing and dispatch, confirm popups
TankTrails/Core/Boot.lua           ADDON_LOADED: defaults, App.new, start   (game only)
TankTrails/Model/Recorder.lua      open/resume/close runs; room, pull, death, target, boss, note events
TankTrails/Model/Route.lua         fold, next, progress, select
TankTrails/Model/Merge.lua         shipped + saved overlay -> effective dungeon
TankTrails/Model/Promote.lua       run log -> route; boss info
TankTrails/Model/Serialize.lua     export text; sandboxed parse; validate
TankTrails/Model/Geometry.lua      bearing, grid, fit, toImage
TankTrails/Wow/Safe.lua            secret stripping
TankTrails/Wow/InstanceWatch.lua   party dungeon id and name from env
TankTrails/Wow/Events.lua          event frame -> handler calls with safe payloads
TankTrails/Wow/Store.lua           SavedVariables access: overlays, runs, routes, notes, import, reset
TankTrails/UI/Theme.lua            colours, fonts
TankTrails/UI/Widgets.lua          box, text, button helpers
TankTrails/UI/TextBox.lua          scrollable edit box window for export/import
TankTrails/UI/Hud.lua              the four-line HUD
TankTrails/Data/Dungeons.xml       include list (empty in this plan)
spec/helpers/fake_env.lua          scriptable env and frame stubs
spec/*_spec.lua                    one per module
tools/install.sh                   rsync into an AddOns folder
docs/superpowers/notes/in-game-checklist.md
.busted  .gitignore  README.md
```

---

### Task 1: Toolchain, scaffold, Util

**Files:**
- Create: `.busted`, `README.md`, `TankTrails/TankTrails.toc`, `TankTrails/Core/Util.lua`, `TankTrails/Core/Init.lua`, `tools/install.sh`
- Test: `spec/util_spec.lua`, `spec/init_spec.lua`

**Interfaces:**
- Produces: `Util.newErrorLog(max)` → log with `:add(label, err)`, `:clear()`, `.entries`; `Util.safeCall(log, label, fn, ...)`; `Util.wrap(log, label, fn)`; `Util.round4(n)`; `Util.round1(n)`; `Util.sortedKeys(t)` → array; `Util.deepCopy(t)`; `Util.trim(s)`; `Util.isArray(t)`.
- Produces: `Init.applyDefaults(target, defaults)`; `Init.ACCOUNT_DEFAULTS`; `Init.CHAR_DEFAULTS`; global `TankTrails_RegisterDungeon(d)` → true/false, storing into `TankTrails.shipped[d.id]`.

- [ ] **Step 1: Install the Lua toolchain**

```bash
cd ~/lua_projects/dungeon_map
python3 -m hererocks .lua -l 5.1 -r latest
.lua/bin/luarocks install busted
.lua/bin/busted --version    # expect 2.x
```

- [ ] **Step 2: Write `.busted` and the TOC**

`.busted`:
```lua
return {
  default = {
    ROOT = { "spec" },
    pattern = "_spec",
    lpath = "TankTrails/?.lua;spec/?.lua",
  },
}
```

`TankTrails/TankTrails.toc` (the load order is final; files not yet written are added as their tasks land, keep this order):
```
## Interface: 16001
## Title: TankTrails
## Notes: Room-level dungeon navigation and tank notes for WoW Forever
## Author: rcrosbourne
## Version: 0.1.0
## SavedVariables: TankTrailsDB
## SavedVariablesPerCharacter: TankTrailsCharDB

Core\Init.lua
Core\Util.lua
Wow\Safe.lua
Wow\InstanceWatch.lua
Model\Geometry.lua
Model\Recorder.lua
Model\Route.lua
Model\Merge.lua
Model\Promote.lua
Model\Serialize.lua
Wow\Store.lua
Wow\Events.lua
UI\Theme.lua
UI\Widgets.lua
UI\TextBox.lua
UI\Hud.lua
Core\App.lua
Core\Commands.lua
Data\Dungeons.xml
Core\Boot.lua
```

- [ ] **Step 3: Write the failing Util and Init tests**

`spec/util_spec.lua`:
```lua
local Util = require("Core.Util")

describe("Util", function()
  it("caps the error log", function()
    local log = Util.newErrorLog(2)
    log:add("a", "1"); log:add("b", "2"); log:add("c", "3")
    assert.are.equal(2, #log.entries)
    assert.are.equal("b", log.entries[1].label)
  end)

  it("safeCall returns results on success and logs on failure", function()
    local log = Util.newErrorLog()
    assert.are.equal(3, Util.safeCall(log, "add", function(a, b) return a + b end, 1, 2))
    assert.is_nil(Util.safeCall(log, "boom", function() error("bad") end))
    assert.are.equal(1, #log.entries)
    assert.truthy(log.entries[1].message:find("bad"))
  end)

  it("rounds, sorts keys, copies deeply, trims", function()
    assert.are.equal(0.1235, Util.round4(0.12345))
    assert.are.equal(8.2, Util.round1(8.24))
    assert.are.same({ "a", "b", "c" }, Util.sortedKeys({ c = 1, a = 2, b = 3 }))
    local src = { rooms = { x = { 1 } } }
    local copy = Util.deepCopy(src)
    copy.rooms.x[1] = 2
    assert.are.equal(1, src.rooms.x[1])
    assert.are.equal("hi", Util.trim("  hi \n"))
    assert.is_true(Util.isArray({ 1, 2 }))
    assert.is_false(Util.isArray({ a = 1 }))
    assert.is_false(Util.isArray({}))
  end)
end)
```

`spec/init_spec.lua`:
```lua
describe("Init", function()
  before_each(function()
    _G.TankTrails = nil
    package.loaded["Core.Init"] = nil
  end)

  it("fills defaults without overwriting", function()
    local Init = require("Core.Init")
    local db = { settings = { autoOpen = false } }
    Init.applyDefaults(db, Init.ACCOUNT_DEFAULTS)
    assert.is_false(db.settings.autoOpen)
    assert.are.equal(1, db.settings.hud.scale)
    assert.are.same({}, db.dungeons)
  end)

  it("registers shipped dungeons by id", function()
    require("Core.Init")
    assert.is_true(TankTrails_RegisterDungeon({ id = 36, name = "The Deadmines" }))
    assert.is_false(TankTrails_RegisterDungeon({ name = "no id" }))
    assert.are.equal("The Deadmines", TankTrails.shipped[36].name)
  end)
end)
```

- [ ] **Step 4: Run them to verify they fail**

Run: `.lua/bin/busted spec/util_spec.lua spec/init_spec.lua`
Expected: errors, `module 'Core.Util' not found`.

- [ ] **Step 5: Write Util and Init**

`TankTrails/Core/Util.lua`:
```lua
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
```

`TankTrails/Core/Init.lua`:
```lua
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
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `.lua/bin/busted spec/util_spec.lua spec/init_spec.lua`
Expected: `5 successes`.

- [ ] **Step 7: Write README and the install script**

`README.md`:
```markdown
# TankTrails

Room-level dungeon navigation and tank notes for WoW Forever. Spec: `docs/superpowers/specs/2026-10-12-tanktrails-design.md`.

## Build
- Toolchain (once): `python3 -m hererocks .lua -l 5.1 -r latest`, then `.lua/bin/luarocks install busted`.
- Tests: `.lua/bin/busted`.

## Install
`tools/install.sh "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"`, then run `docs/superpowers/notes/in-game-checklist.md`.

## Commands
See `/tt` in game, or spec §7.5.

## Layout
- `TankTrails/Model` pure logic, `TankTrails/Wow` game adapters, `TankTrails/UI` frames, `TankTrails/Core` wiring, `TankTrails/Data` shipped dungeons.
```

`tools/install.sh`:
```bash
#!/usr/bin/env bash
# Copies the addon into a WoW AddOns folder.
# Usage: tools/install.sh "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"
set -euo pipefail
dest="${1:?Usage: tools/install.sh <path to Interface/AddOns>}"
dest="${dest%/}"
case "$dest" in
  */AddOns) ;;
  *) echo "Refusing: $dest is not an AddOns folder" >&2; exit 1 ;;
esac
[ -d "$dest" ] || { echo "No such folder: $dest" >&2; exit 1; }
cd "$(dirname "$0")/.."
rsync -a --delete --exclude '.DS_Store' TankTrails/ "$dest/TankTrails/"
echo "Installed TankTrails to $dest/TankTrails"
```

Run: `chmod +x tools/install.sh`

- [ ] **Step 8: Commit**

```bash
git add .busted README.md TankTrails tools spec
git commit -m "Scaffold TankTrails: toolchain, TOC, Util, Init"
```

---

### Task 2: Fake env helper and Wow/Safe

**Files:**
- Create: `spec/helpers/fake_env.lua`, `TankTrails/Wow/Safe.lua`
- Test: `spec/safe_spec.lua`

**Interfaces:**
- Produces: `fake_env.new(state)` → `env, state`; `fake_env.frame()` → frame stub with `:RegisterEvent`, `:UnregisterAllEvents`, `:SetScript`, `:fire(event, ...)`.
- Produces: `Safe.value(env, v)` → v or nil; `Safe.string(env, v)` → non-empty string or nil; `Safe.number(env, v)` → number or nil.

- [ ] **Step 1: Write the fake env**

`spec/helpers/fake_env.lua`:
```lua
local M = {}

-- A scriptable stand-in for the game globals the adapters read.
-- state: secrets (set of values that are secret), zoneText, instance = { kind, name, id } or nil,
--        target = { isPlayer, name } or nil, now (seconds), chat (messages printed), ticker (fn), popup.
function M.new(state)
  state = state or {}
  state.secrets = state.secrets or {}
  state.chat = state.chat or {}
  local env = {}
  env.issecretvalue = function(v) return state.secrets[v] == true end
  env.GetMinimapZoneText = function() return state.zoneText end
  env.IsInInstance = function()
    if not state.instance then return false, "none" end
    return true, state.instance.kind or "party"
  end
  env.GetInstanceInfo = function()
    local i = state.instance
    if not i then return nil end
    return i.name, i.kind or "party", 1, "Normal", 5, 0, false, i.id
  end
  env.UnitExists = function() return state.target ~= nil end
  env.UnitIsPlayer = function() return state.target ~= nil and state.target.isPlayer == true end
  env.UnitName = function() return state.target and state.target.name end
  env.CreateFrame = function() return M.frame() end
  env.C_Timer = { NewTicker = function(_, fn)
    state.ticker = fn
    return { Cancel = function() state.ticker = nil end }
  end }
  env.time = function() return state.now or 0 end
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(state.chat, msg) end }
  env.StaticPopupDialogs = {}
  env.StaticPopup_Show = function(which, text1, text2, data)
    state.popup = { which = which, data = data }
    return {}
  end
  return env, state
end

function M.frame()
  local f = { events = {}, scripts = {}, shown = true }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterAllEvents() self.events = {} end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:fire(event, ...)
    if self.scripts.OnEvent then self.scripts.OnEvent(self, event, ...) end
  end
  return f
end

return M
```

- [ ] **Step 2: Write the failing Safe test**

`spec/safe_spec.lua`:
```lua
local fake = require("helpers.fake_env")
local Safe = require("Wow.Safe")

describe("Safe", function()
  it("passes ordinary values and drops secret ones", function()
    local env, state = fake.new()
    state.secrets["Rhahk'Zor"] = true
    assert.are.equal("Mast Room", Safe.value(env, "Mast Room"))
    assert.is_nil(Safe.value(env, "Rhahk'Zor"))
    assert.are.equal(7, Safe.number(env, 7))
  end)

  it("works on a client without issecretvalue", function()
    local env = fake.new()
    env.issecretvalue = nil
    assert.are.equal("x", Safe.string(env, "x"))
  end)

  it("string rejects empty text and non-strings; number rejects non-numbers", function()
    local env = fake.new()
    assert.is_nil(Safe.string(env, ""))
    assert.is_nil(Safe.string(env, 5))
    assert.is_nil(Safe.number(env, "5"))
    assert.is_nil(Safe.value(env, nil))
  end)
end)
```

- [ ] **Step 3: Run it to verify it fails**

Run: `.lua/bin/busted spec/safe_spec.lua`
Expected: `module 'Wow.Safe' not found`.

- [ ] **Step 4: Write Safe**

`TankTrails/Wow/Safe.lua`:
```lua
local _, ns = ...
ns = ns or {}

local Safe = {}
ns.Safe = Safe

-- nil for any value the client marks secret (Midnight secret values, spec §3); the value otherwise.
function Safe.value(env, v)
  local check = env.issecretvalue
  if v ~= nil and check and check(v) then return nil end
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
```

- [ ] **Step 5: Run it to verify it passes**

Run: `.lua/bin/busted spec/safe_spec.lua`
Expected: `3 successes`.

- [ ] **Step 6: Commit**

```bash
git add spec/helpers/fake_env.lua spec/safe_spec.lua TankTrails/Wow/Safe.lua
git commit -m "Add fake env helper and Wow/Safe secret stripping"
```

---

### Task 3: Wow/InstanceWatch

**Files:**
- Create: `TankTrails/Wow/InstanceWatch.lua`
- Test: `spec/instance_watch_spec.lua`

**Interfaces:**
- Consumes: `Safe.string`, `Safe.number`.
- Produces: `InstanceWatch.current(env)` → `id, name` for a party dungeon, else nil.

- [ ] **Step 1: Write the failing test**

`spec/instance_watch_spec.lua`:
```lua
local fake = require("helpers.fake_env")
local InstanceWatch = require("Wow.InstanceWatch")

describe("InstanceWatch.current", function()
  it("returns nil outside instances", function()
    local env = fake.new()
    assert.is_nil(InstanceWatch.current(env))
  end)

  it("returns nil in raids", function()
    local env = fake.new({ instance = { kind = "raid", name = "Onyxia's Lair", id = 249 } })
    assert.is_nil(InstanceWatch.current(env))
  end)

  it("returns id and name in a party dungeon", function()
    local env = fake.new({ instance = { name = "The Deadmines", id = 36 } })
    local id, name = InstanceWatch.current(env)
    assert.are.equal(36, id)
    assert.are.equal("The Deadmines", name)
  end)

  it("returns nil while the name or id is missing during loading", function()
    local env = fake.new({ instance = { name = nil, id = 36 } })
    assert.is_nil(InstanceWatch.current(env))
    env = fake.new({ instance = { name = "The Deadmines", id = nil } })
    assert.is_nil(InstanceWatch.current(env))
  end)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `.lua/bin/busted spec/instance_watch_spec.lua`
Expected: `module 'Wow.InstanceWatch' not found`.

- [ ] **Step 3: Write InstanceWatch**

`TankTrails/Wow/InstanceWatch.lua`:
```lua
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `.lua/bin/busted spec/instance_watch_spec.lua`
Expected: `4 successes`.

- [ ] **Step 5: Commit**

```bash
git add spec/instance_watch_spec.lua TankTrails/Wow/InstanceWatch.lua
git commit -m "Add Wow/InstanceWatch"
```

---

### Task 4: Model/Recorder

**Files:**
- Create: `TankTrails/Model/Recorder.lua`
- Test: `spec/recorder_spec.lua`

**Interfaces:**
- Consumes: `Util.round1`.
- Produces (all pure; `now` is wall-clock seconds from `env.time()`):
  - `Recorder.open(saved, id, name, now)` → `run, stale`: resumes `saved` when it is for `id` and has no `endedAt`; otherwise a new run, and `stale` is the old unfinished run with `endedAt` set, for filing.
  - `Recorder.close(run, now)` → sets `endedAt`, closes an open pull.
  - `Recorder.room(run, text, now)` → room event or nil (nil for empty text or no change).
  - `Recorder.currentRoom(run)` → last room text or nil.
  - `Recorder.target(run, name, now)` → remembers the out-of-combat target; nil clears.
  - `Recorder.pullStart(run, now)` → pull event or nil if one is open; attaches `target` seen within 10 s.
  - `Recorder.pullEnd(run, now)` → the closed pull or nil.
  - `Recorder.death(run)` → true if counted against an open pull.
  - `Recorder.boss(run, name, encounterID, now, manual)` → boss event, or nil when unidentifiable or a duplicate within 5 s.
  - `Recorder.note(run, text, now)` → note event.
  - `Recorder.counts(run)` → `{ rooms = n, bosses = n }` (distinct rooms, boss events).
- Run shape (spec §5.2): `{ dungeon, name, startedAt, endedAt, routeName, events = {...}, lastRoom, pull, lastTarget, lastBoss }`. The last four are working fields and are dropped by `Serialize`/`Store` never; they are harmless in SavedVariables.

- [ ] **Step 1: Write the failing tests**

`spec/recorder_spec.lua`:
```lua
local Recorder = require("Model.Recorder")

local function newRun(now)
  local run = Recorder.open(nil, 36, "The Deadmines", now or 1000)
  return run
end

describe("Recorder.open", function()
  it("starts a new run when nothing is saved", function()
    local run, stale = Recorder.open(nil, 36, "The Deadmines", 1000)
    assert.are.equal(36, run.dungeon)
    assert.are.equal("The Deadmines", run.name)
    assert.are.equal(1000, run.startedAt)
    assert.are.same({}, run.events)
    assert.is_nil(stale)
  end)

  it("resumes an unfinished run for the same dungeon", function()
    local saved = { dungeon = 36, name = "The Deadmines", startedAt = 900, events = { { t = 1, kind = "room", room = "A" } } }
    local run, stale = Recorder.open(saved, 36, "The Deadmines", 1000)
    assert.are.equal(saved, run)
    assert.is_nil(stale)
  end)

  it("files an unfinished run for another dungeon as stale", function()
    local saved = { dungeon = 43, name = "Wailing Caverns", startedAt = 900, events = {} }
    local run, stale = Recorder.open(saved, 36, "The Deadmines", 1000)
    assert.are.equal(36, run.dungeon)
    assert.are.equal(saved, stale)
    assert.are.equal(1000, stale.endedAt)
  end)

  it("does not resume a run that already ended", function()
    local saved = { dungeon = 36, name = "The Deadmines", startedAt = 900, endedAt = 950, events = {} }
    local run, stale = Recorder.open(saved, 36, "The Deadmines", 1000)
    assert.are_not.equal(saved, run)
    assert.is_nil(stale)
  end)
end)

describe("Recorder rooms", function()
  it("emits a room event only when the text changes, never for empty text", function()
    local run = newRun(1000)
    assert.is_nil(Recorder.room(run, nil, 1001))
    assert.is_nil(Recorder.room(run, "", 1001))
    local ev = Recorder.room(run, "The Deadmines", 1002.46)
    assert.are.same({ t = 2.5, kind = "room", room = "The Deadmines" }, ev)
    assert.is_nil(Recorder.room(run, "The Deadmines", 1003))
    assert.are.equal("Mast Room", Recorder.room(run, "Mast Room", 1010).room)
    assert.are.equal("Mast Room", Recorder.currentRoom(run))
    assert.are.equal(2, #run.events)
  end)
end)

describe("Recorder pulls", function()
  it("opens and closes a pull with duration and room, counting deaths", function()
    local run = newRun(1000)
    Recorder.room(run, "Mast Room", 1001)
    local pull = Recorder.pullStart(run, 1010)
    assert.are.equal("Mast Room", pull.room)
    assert.are.equal(0, pull.deaths)
    assert.is_nil(Recorder.pullStart(run, 1011))   -- already open
    assert.is_true(Recorder.death(run))
    assert.are.equal(pull, Recorder.pullEnd(run, 1018.2))
    assert.are.equal(8.2, pull.duration)
    assert.are.equal(1, pull.deaths)
    assert.is_false(Recorder.death(run))            -- nothing open
    assert.is_nil(Recorder.pullEnd(run, 1020))
  end)

  it("attaches the out-of-combat target seen within ten seconds", function()
    local run = newRun(1000)
    Recorder.target(run, "Defias Miner", 1005)
    local pull = Recorder.pullStart(run, 1014)
    assert.are.equal("Defias Miner", pull.target)
    Recorder.pullEnd(run, 1020)
    Recorder.target(run, "Defias Overseer", 1021)
    pull = Recorder.pullStart(run, 1032)             -- 11 s later
    assert.is_nil(pull.target)
    Recorder.pullEnd(run, 1040)
    Recorder.target(run, "Goblin Craftsman", 1041)
    Recorder.target(run, nil, 1042)                  -- target cleared
    pull = Recorder.pullStart(run, 1043)
    assert.is_nil(pull.target)
  end)
end)

describe("Recorder bosses", function()
  it("records a boss with name, id and room; de-duplicates within five seconds", function()
    local run = newRun(1000)
    Recorder.room(run, "The Deadmines", 1001)
    local ev = Recorder.boss(run, "Rhahk'Zor", 1234, 1100)
    assert.are.same({ t = 100, kind = "boss", name = "Rhahk'Zor", encounterID = 1234, room = "The Deadmines" }, ev)
    assert.is_nil(Recorder.boss(run, "Rhahk'Zor", 1234, 1102))     -- ENCOUNTER_END then BOSS_KILL
    assert.is_nil(Recorder.boss(run, "Rhahk'Zor", nil, 1103))      -- same name, no id
    assert.is_not_nil(Recorder.boss(run, "Rhahk'Zor", 1234, 1106)) -- past the window
  end)

  it("ignores a boss with no identity", function()
    local run = newRun(1000)
    assert.is_nil(Recorder.boss(run, nil, nil, 1100))
    assert.are.same({}, run.events)
  end)

  it("records a manual tick", function()
    local run = newRun(1000)
    local ev = Recorder.boss(run, "Cookie", nil, 1400, true)
    assert.is_true(ev.manual)
    assert.are.equal("Cookie", ev.name)
  end)
end)

describe("Recorder notes, close, counts", function()
  it("writes a note event for the current room", function()
    local run = newRun(1000)
    Recorder.room(run, "Ironclad Cove", 1001)
    local ev = Recorder.note(run, "Clear the deck first", 1050)
    assert.are.same({ t = 50, kind = "note", room = "Ironclad Cove", text = "Clear the deck first" }, ev)
  end)

  it("close sets endedAt and ends an open pull", function()
    local run = newRun(1000)
    Recorder.pullStart(run, 1010)
    Recorder.close(run, 1020)
    assert.are.equal(1020, run.endedAt)
    assert.are.equal(10, run.events[1].duration)
    assert.is_nil(run.pull)
  end)

  it("counts distinct rooms and boss events", function()
    local run = newRun(1000)
    Recorder.room(run, "A", 1001); Recorder.room(run, "B", 1002); Recorder.room(run, "A", 1003)
    Recorder.boss(run, "X", nil, 1010)
    assert.are.same({ rooms = 2, bosses = 1 }, Recorder.counts(run))
  end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted spec/recorder_spec.lua`
Expected: `module 'Model.Recorder' not found`.

- [ ] **Step 3: Write Recorder**

`TankTrails/Model/Recorder.lua`:
```lua
local _, ns = ...
ns = ns or {}
local Util = ns.Util or require("Core.Util")

local Recorder = {}
ns.Recorder = Recorder

Recorder.BOSS_WINDOW = 5     -- seconds: two boss events with one identity are one kill (spec §6.3)
Recorder.TARGET_WINDOW = 10  -- seconds: a pull takes the last out-of-combat target this recent (spec §6.4)

local function stamp(run, now) return Util.round1(now - run.startedAt) end

local function push(run, ev)
  table.insert(run.events, ev)
  return ev
end

-- Resume saved when it is this dungeon's unfinished run; otherwise start fresh and hand back the
-- unfinished one, ended, for filing (spec §6.1).
function Recorder.open(saved, id, name, now)
  if saved and saved.dungeon == id and not saved.endedAt then return saved, nil end
  local stale
  if saved and not saved.endedAt then
    saved.endedAt = now
    stale = saved
  end
  return { dungeon = id, name = name, startedAt = now, events = {} }, stale
end

function Recorder.close(run, now)
  Recorder.pullEnd(run, now)
  run.endedAt = now
end

function Recorder.room(run, text, now)
  if type(text) ~= "string" or text == "" or text == run.lastRoom then return nil end
  run.lastRoom = text
  return push(run, { t = stamp(run, now), kind = "room", room = text })
end

function Recorder.currentRoom(run) return run.lastRoom end

function Recorder.target(run, name, now)
  if name then run.lastTarget = { name = name, at = now } else run.lastTarget = nil end
end

function Recorder.pullStart(run, now)
  if run.pull then return nil end
  local ev = { t = stamp(run, now), kind = "pull", room = run.lastRoom, deaths = 0 }
  local target = run.lastTarget
  if target and now - target.at <= Recorder.TARGET_WINDOW then ev.target = target.name end
  run.pull = ev
  return push(run, ev)
end

function Recorder.pullEnd(run, now)
  local pull = run.pull
  if not pull then return nil end
  pull.duration = Util.round1(now - (run.startedAt + pull.t))
  run.pull = nil
  return pull
end

function Recorder.death(run)
  if not run.pull then return false end
  run.pull.deaths = run.pull.deaths + 1
  return true
end

function Recorder.boss(run, name, encounterID, now, manual)
  local key = encounterID or name
  if key == nil then return nil end
  local last = run.lastBoss
  if last and now - last.at <= Recorder.BOSS_WINDOW and (last.id == encounterID or last.name == name) then
    return nil
  end
  run.lastBoss = { id = encounterID, name = name, at = now }
  local ev = { t = stamp(run, now), kind = "boss", name = name, encounterID = encounterID, room = run.lastRoom }
  if manual then ev.manual = true end
  return push(run, ev)
end

function Recorder.note(run, text, now)
  return push(run, { t = stamp(run, now), kind = "note", room = run.lastRoom, text = text })
end

function Recorder.counts(run)
  local rooms, bosses = {}, 0
  for _, ev in ipairs(run.events) do
    if ev.kind == "room" then rooms[ev.room] = true elseif ev.kind == "boss" then bosses = bosses + 1 end
  end
  local n = 0
  for _ in pairs(rooms) do n = n + 1 end
  return { rooms = n, bosses = bosses }
end

return Recorder
```

- [ ] **Step 4: Run them to verify they pass**

Run: `.lua/bin/busted spec/recorder_spec.lua`
Expected: `13 successes`.

- [ ] **Step 5: Commit**

```bash
git add spec/recorder_spec.lua TankTrails/Model/Recorder.lua
git commit -m "Add Model/Recorder: runs, rooms, pulls, bosses, notes"
```

---

### Task 5: Model/Route (cursor, next, progress, selection)

**Files:**
- Create: `TankTrails/Model/Route.lua`
- Test: `spec/route_spec.lua`

**Interfaces:**
- Produces (pure):
  - `Route.newState()` → `{ cursor = 0, done = {}, offRoute = nil, unexpected = {} }`.
  - `Route.apply(route, state, ev, bosses)` → state, applying one event per spec §6.5. `bosses` is `dungeon.bosses` (for encounter-id matching).
  - `Route.fold(route, events, bosses)` → fresh state folded over all events.
  - `Route.next(route, state)` → step index or nil (route complete).
  - `Route.progress(route, state)` → `done, total` boss counts.
  - `Route.select(dungeon, activeName, events)` → route or nil when the dungeon has none (spec §6.6).
  - `Route.bossMatches(step, ev, bosses)` → boolean.

- [ ] **Step 1: Write the failing tests**

`spec/route_spec.lua`:
```lua
local Route = require("Model.Route")

local ROUTE = { name = "Standard", steps = {
  { room = "The Deadmines", note = "first packs" },  -- 1
  { boss = "Rhahk'Zor" },                            -- 2
  { room = "Mast Room", note = "ramp patrol" },      -- 3
  { boss = "Sneed" },                                -- 4
  { room = "Goblin Foundry" },                       -- 5
  { boss = "Gilnid" },                               -- 6
  { room = "Ironclad Cove" },                        -- 7
  { boss = "Mr. Smite" },                            -- 8
} }
local BOSSES = { ["Rhahk'Zor"] = { encounterID = 1234 } }

local function room(r) return { kind = "room", room = r } end
local function boss(n, id) return { kind = "boss", name = n, encounterID = id } end

describe("Route.fold", function()
  it("moves forward to the nearest matching room", function()
    local s = Route.fold(ROUTE, { room("The Deadmines"), room("Mast Room") })
    assert.are.equal(3, s.cursor)
    assert.is_nil(s.offRoute)
  end)

  it("backtracks to the nearest earlier room", function()
    local s = Route.fold(ROUTE, { room("Goblin Foundry"), room("Mast Room") })
    assert.are.equal(3, s.cursor)
  end)

  it("marks an unknown room off route without moving", function()
    local s = Route.fold(ROUTE, { room("Mast Room"), room("Secret Cave") })
    assert.are.equal(3, s.cursor)
    assert.are.equal("Secret Cave", s.offRoute)
    s = Route.apply(ROUTE, s, room("Goblin Foundry"))
    assert.is_nil(s.offRoute)
  end)

  it("re-anchors on a boss ahead, skipping rooms never seen", function()
    local s = Route.fold(ROUTE, { room("The Deadmines"), boss("Gilnid") }, BOSSES)
    assert.are.equal(6, s.cursor)
    assert.is_true(s.done[6])
  end)

  it("marks a boss killed behind the cursor and moves back to it", function()
    local s = Route.fold(ROUTE, { room("Goblin Foundry"), boss("Rhahk'Zor", 1234) }, BOSSES)
    assert.are.equal(2, s.cursor)
    assert.is_true(s.done[2])
  end)

  it("matches by encounter id when both sides have one, else by name", function()
    assert.is_true(Route.bossMatches({ boss = "Rhahk'Zor" }, boss("secret-name-stripped", 1234), BOSSES))
    assert.is_false(Route.bossMatches({ boss = "Rhahk'Zor" }, boss("Rhahk'Zor", 9999), BOSSES))
    assert.is_true(Route.bossMatches({ boss = "Sneed" }, boss("Sneed", 4321), BOSSES))
    assert.is_false(Route.bossMatches({ room = "Mast Room" }, boss("Sneed"), BOSSES))
  end)

  it("collects bosses that are in no step", function()
    local s = Route.fold(ROUTE, { boss("Cookie"), boss(nil, 77) })
    assert.are.same({ "Cookie", "#77" }, s.unexpected)
    assert.are.equal(0, s.cursor)
  end)

  it("ignores pulls and notes", function()
    local s = Route.fold(ROUTE, { room("Mast Room"), { kind = "pull", room = "Mast Room" }, { kind = "note", text = "x" } })
    assert.are.equal(3, s.cursor)
  end)

  it("is deterministic: the same events give the same state", function()
    local evs = { room("The Deadmines"), boss("Rhahk'Zor", 1234), room("Mast Room"), boss("Sneed") }
    assert.are.same(Route.fold(ROUTE, evs, BOSSES), Route.fold(ROUTE, evs, BOSSES))
  end)
end)

describe("Route.next and progress", function()
  it("skips done bosses and reports completion", function()
    local s = Route.fold(ROUTE, { room("Goblin Foundry"), boss("Gilnid") })
    assert.are.equal(7, Route.next(ROUTE, s))
    s = Route.fold(ROUTE, { room("The Deadmines"), boss("Sneed") })
    assert.are.equal(5, Route.next(ROUTE, s))
    s = Route.fold(ROUTE, { room("Ironclad Cove"), boss("Mr. Smite") })
    assert.is_nil(Route.next(ROUTE, s))
    local done, total = Route.progress(ROUTE, s)
    assert.are.equal(1, done)
    assert.are.equal(4, total)
  end)

  it("reports the step after a done boss that sits behind the cursor", function()
    local s = Route.fold(ROUTE, { room("Mast Room"), boss("Rhahk'Zor", 1234) }, BOSSES)
    assert.are.equal(3, Route.next(ROUTE, s))
  end)
end)

describe("Route.select", function()
  local GY = { name = "Graveyard", steps = { { room = "Scarlet Monastery" }, { room = "Chamber of Atonement" }, { boss = "Bloodmage Thalnos" } } }
  local LIB = { name = "Library", steps = { { room = "Scarlet Monastery" }, { room = "Huntsman's Cloister" }, { boss = "Houndmaster Loksey" } } }
  local SM = { id = 189, name = "Scarlet Monastery", routes = { GY, LIB } }

  it("returns nil when the dungeon has no routes", function()
    assert.is_nil(Route.select({ id = 1, routes = {} }, nil, {}))
  end)

  it("uses the active route, else the first", function()
    assert.are.equal(LIB, Route.select(SM, "Library", {}))
    assert.are.equal(GY, Route.select(SM, nil, {}))
  end)

  it("falls back to the first route when activeRoute is missing", function()
    assert.are.equal(GY, Route.select(SM, "Armory", {}))
  end)

  it("switches on an unmatched room before the first boss, then stays", function()
    local evs = { room("Scarlet Monastery"), room("Huntsman's Cloister") }
    assert.are.equal(LIB, Route.select(SM, "Graveyard", evs))
    evs = { room("Scarlet Monastery"), boss("Bloodmage Thalnos"), room("Huntsman's Cloister") }
    assert.are.equal(GY, Route.select(SM, "Graveyard", evs))
  end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted spec/route_spec.lua`
Expected: `module 'Model.Route' not found`.

- [ ] **Step 3: Write Route**

`TankTrails/Model/Route.lua`:
```lua
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
```

- [ ] **Step 4: Run them to verify they pass**

Run: `.lua/bin/busted spec/route_spec.lua`
Expected: `15 successes`.

- [ ] **Step 5: Commit**

```bash
git add spec/route_spec.lua TankTrails/Model/Route.lua
git commit -m "Add Model/Route: cursor fold, next, progress, route selection"
```

---

### Task 6: Model/Merge

**Files:**
- Create: `TankTrails/Model/Merge.lua`
- Test: `spec/merge_spec.lua`

**Interfaces:**
- Consumes: `Util.deepCopy`.
- Produces: `Merge.effective(shipped, saved, id, name)` → effective dungeon per spec §5.4, always with `rooms`, `bosses`, `routes` tables; never aliases its inputs.

- [ ] **Step 1: Write the failing tests**

`spec/merge_spec.lua`:
```lua
local Merge = require("Model.Merge")

local SHIPPED = { id = 36, name = "The Deadmines", art = { kind = "native", floors = { { name = "Mines", uiMapID = 291 } } },
  rooms = { ["Mast Room"] = { floor = 1, x = 0.4, y = 0.6 }, ["Goblin Foundry"] = { floor = 1, x = 0.6, y = 0.3 } },
  bosses = { ["Sneed"] = { room = "Mast Room" } },
  routes = { { name = "Standard", steps = { { room = "Mast Room" } } }, { name = "Fast", steps = { { room = "Goblin Foundry" } } } } }

describe("Merge.effective", function()
  it("creates a minimal dungeon when nothing shipped and nothing saved", function()
    assert.are.same({ id = 1, name = "Cave", rooms = {}, bosses = {}, routes = {} }, Merge.effective(nil, nil, 1, "Cave"))
  end)

  it("copies shipped data without aliasing", function()
    local d = Merge.effective(SHIPPED, nil, 36, "x")
    assert.are.same(SHIPPED.rooms, d.rooms)
    d.rooms["Mast Room"].x = 0
    assert.are.equal(0.4, SHIPPED.rooms["Mast Room"].x)
    assert.are.equal("The Deadmines", d.name)
  end)

  it("lets saved win per room, per boss and per route name, keeping shipped-only routes", function()
    local saved = { rooms = { ["Mast Room"] = { floor = 1, x = 0.41, y = 0.61 } },
      bosses = { ["Sneed"] = { room = "Mast Room", encounterID = 5 } },
      routes = { { name = "Standard", steps = { { room = "Mast Room", note = "mine" } } }, { name = "Recorded", steps = {} } },
      activeRoute = "Recorded" }
    local d = Merge.effective(SHIPPED, saved, 36, "x")
    assert.are.equal(0.41, d.rooms["Mast Room"].x)
    assert.are.equal(0.6, d.rooms["Goblin Foundry"].x)
    assert.are.equal(5, d.bosses["Sneed"].encounterID)
    assert.are.equal(3, #d.routes)
    assert.are.equal("mine", d.routes[1].steps[1].note)
    assert.are.equal("Fast", d.routes[2].name)
    assert.are.equal("Recorded", d.routes[3].name)
    assert.are.equal("Recorded", d.activeRoute)
  end)

  it("takes saved name and art when set", function()
    local d = Merge.effective(SHIPPED, { name = "Deadmines (beta)", art = { kind = "none" } }, 36, "x")
    assert.are.equal("Deadmines (beta)", d.name)
    assert.are.same({ kind = "none" }, d.art)
    d = Merge.effective(SHIPPED, {}, 36, "x")
    assert.are.equal("native", d.art.kind)
  end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted spec/merge_spec.lua`
Expected: `module 'Model.Merge' not found`.

- [ ] **Step 3: Write Merge**

`TankTrails/Model/Merge.lua`:
```lua
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
```

- [ ] **Step 4: Run them to verify they pass**

Run: `.lua/bin/busted spec/merge_spec.lua`
Expected: `4 successes`.

- [ ] **Step 5: Commit**

```bash
git add spec/merge_spec.lua TankTrails/Model/Merge.lua
git commit -m "Add Model/Merge: shipped plus saved overlay"
```

---

### Task 7: Model/Promote (run log to route)

**Files:**
- Create: `TankTrails/Model/Promote.lua`
- Test: `spec/promote_spec.lua`

**Interfaces:**
- Produces: `Promote.run(run, oldRoute, name, today, now)` → `route, bossInfo` or `nil, nil, err`. `today` is a `YYYY-MM-DD` string (the caller formats it), `now` wall-clock seconds for an unfinished run. `bossInfo` is `{ [bossKey] = { room, encounterID } }`. A boss whose name was secret gets the key `"#<encounterID>"`.

- [ ] **Step 1: Write the failing tests**

`spec/promote_spec.lua`:
```lua
local Promote = require("Model.Promote")

local function run(events, endedAt)
  return { dungeon = 36, name = "The Deadmines", startedAt = 1000, endedAt = endedAt, events = events }
end
local function room(t, r) return { t = t, kind = "room", room = r } end
local function boss(t, n, id, r) return { t = t, kind = "boss", name = n, encounterID = id, room = r } end

describe("Promote.run", function()
  it("refuses an empty run", function()
    local route, info, err = Promote.run(run({}), nil, nil, "2026-10-12", 2000)
    assert.is_nil(route)
    assert.is_nil(info)
    assert.are.equal("Nothing recorded in this run", err)
  end)

  it("keeps rooms in order and names the route by date", function()
    local route = Promote.run(run({ room(0, "A"), room(30, "B"), room(60, "C") }, 1100), nil, nil, "2026-10-12", 1100)
    assert.are.equal("Recorded 2026-10-12", route.name)
    assert.are.same({ { room = "A" }, { room = "B" }, { room = "C" } }, route.steps)
    route = Promote.run(run({ room(0, "A") }, 1100), nil, "Mine", "2026-10-12", 1100)
    assert.are.equal("Mine", route.name)
  end)

  it("collapses a flap under fifteen seconds and keeps one over", function()
    local route = Promote.run(run({ room(0, "A"), room(30, "B"), room(40, "A"), room(100, "C") }, 1200), nil, nil, "d", 1200)
    assert.are.same({ { room = "A" }, { room = "C" } }, route.steps)
    route = Promote.run(run({ room(0, "A"), room(30, "B"), room(50, "A"), room(100, "C") }, 1200), nil, nil, "d", 1200)
    assert.are.same({ { room = "A" }, { room = "B" }, { room = "A" }, { room = "C" } }, route.steps)
  end)

  it("merges consecutive duplicates and uses now for an unfinished run's last stay", function()
    local route = Promote.run(run({ room(0, "A"), room(20, "A"), room(40, "B") }), nil, nil, "d", 1041)
    assert.are.same({ { room = "A" }, { room = "B" } }, route.steps)
  end)

  it("interleaves bosses by the room they fell in, including before the first room and after the last", function()
    local evs = { boss(1, "Gatekeeper", nil, nil), room(5, "A"), room(30, "B"), room(40, "A"), boss(45, "X", 7, "A"),
                  room(100, "C"), boss(130, "Y", nil, "C"), boss(131, nil, 99, "C") }
    local route, info = Promote.run(run(evs, 1200), nil, nil, "d", 1200)
    assert.are.same({ { boss = "Gatekeeper" }, { room = "A" }, { boss = "X" }, { room = "C" }, { boss = "Y" }, { boss = "#99" } }, route.steps)
    assert.are.same({ room = "A", encounterID = 7 }, info["X"])
    assert.are.same({ room = "C", encounterID = 99 }, info["#99"])
    assert.are.same({ room = nil, encounterID = nil }, info["Gatekeeper"])
  end)

  it("puts a learning-mode note on the first step of its room", function()
    local evs = { room(0, "A"), { t = 10, kind = "note", room = "A", text = "pull back" }, room(30, "B"), room(60, "A") }
    local route = Promote.run(run(evs, 1100), nil, nil, "d", 1100)
    assert.are.equal("pull back", route.steps[1].note)
    assert.is_nil(route.steps[3].note)
  end)

  it("carries notes over from the old route by kind and key, each old step once", function()
    local old = { name = "Recorded d", steps = { { room = "A", note = "one" }, { boss = "X", note = "boss" }, { room = "A", note = "two" } } }
    local evs = { room(0, "A"), boss(10, "X", nil, "A"), room(30, "B"), room(60, "A"), room(90, "A") }
    local route = Promote.run(run(evs, 1200), old, nil, "d", 1200)
    assert.are.equal("one", route.steps[1].note)
    assert.are.equal("boss", route.steps[2].note)
    assert.is_nil(route.steps[3].note)
    assert.are.equal("two", route.steps[4].note)
  end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted spec/promote_spec.lua`
Expected: `module 'Model.Promote' not found`.

- [ ] **Step 3: Write Promote**

`TankTrails/Model/Promote.lua`:
```lua
local _, ns = ...
ns = ns or {}

local Promote = {}
ns.Promote = Promote
Promote.FLAP = 15  -- seconds (spec §6.8 step 2)

local function bossKey(ev) return ev.name or ("#" .. tostring(ev.encounterID)) end

-- Room events with how long each stay lasted; the last stay ends at endedAt or now.
local function stays(run, now)
  local endT = (run.endedAt or now) - run.startedAt
  local rooms = {}
  for _, ev in ipairs(run.events) do
    if ev.kind == "room" then rooms[#rooms + 1] = { room = ev.room, t = ev.t } end
  end
  for i, r in ipairs(rooms) do
    local nextT = rooms[i + 1] and rooms[i + 1].t or endT
    r.stay = math.max(0, nextT - r.t)
  end
  return rooms
end

-- A, B, A with a short B is a flap: drop B and fold both A stays together. Then merge A, A.
local function collapse(rooms)
  local changed = true
  while changed do
    changed = false
    for i = 2, #rooms - 1 do
      if rooms[i - 1].room == rooms[i + 1].room and rooms[i].stay < Promote.FLAP then
        rooms[i - 1].stay = rooms[i - 1].stay + rooms[i].stay + rooms[i + 1].stay
        table.remove(rooms, i + 1)
        table.remove(rooms, i)
        changed = true
        break
      end
    end
  end
  local out = {}
  for _, r in ipairs(rooms) do
    local last = out[#out]
    if last and last.room == r.room then last.stay = last.stay + r.stay else out[#out + 1] = r end
  end
  return out
end

-- Index of the last room entered at or before t; 0 when t is before the first room.
local function roomIndexAt(rooms, t)
  local idx = 0
  for i, r in ipairs(rooms) do
    if r.t <= t then idx = i else break end
  end
  return idx
end

function Promote.run(run, oldRoute, name, today, now)
  local rooms = collapse(stays(run, now))
  local bosses, notes = {}, {}
  for _, ev in ipairs(run.events) do
    if ev.kind == "boss" and (ev.name or ev.encounterID) then
      bosses[#bosses + 1] = ev
    elseif ev.kind == "note" and ev.room and notes[ev.room] == nil then
      notes[ev.room] = ev.text
    end
  end
  if #rooms == 0 and #bosses == 0 then return nil, nil, "Nothing recorded in this run" end

  local byRoom = {}
  for _, b in ipairs(bosses) do
    local i = roomIndexAt(rooms, b.t)
    byRoom[i] = byRoom[i] or {}
    table.insert(byRoom[i], b)
  end

  local steps = {}
  local function addBosses(i)
    for _, b in ipairs(byRoom[i] or {}) do steps[#steps + 1] = { boss = bossKey(b) } end
  end
  addBosses(0)
  local noted = {}
  for i, r in ipairs(rooms) do
    local step = { room = r.room }
    if notes[r.room] and not noted[r.room] then step.note, noted[r.room] = notes[r.room], true end
    steps[#steps + 1] = step
    addBosses(i)
  end

  if oldRoute then
    local used = {}
    for _, s in ipairs(steps) do
      if not s.note then
        for j, o in ipairs(oldRoute.steps or {}) do
          if not used[j] and o.note and ((s.room and o.room == s.room) or (s.boss and o.boss == s.boss)) then
            s.note, used[j] = o.note, true
            break
          end
        end
      end
    end
  end

  local info = {}
  for _, b in ipairs(bosses) do info[bossKey(b)] = { room = b.room, encounterID = b.encounterID } end
  return { name = name or ("Recorded " .. today), steps = steps }, info
end

return Promote
```

- [ ] **Step 4: Run them to verify they pass**

Run: `.lua/bin/busted spec/promote_spec.lua`
Expected: `7 successes`.

- [ ] **Step 5: Commit**

```bash
git add spec/promote_spec.lua TankTrails/Model/Promote.lua
git commit -m "Add Model/Promote: run log to route"
```

---

### Task 8: Model/Serialize (export, sandboxed import, validation)

**Files:**
- Create: `TankTrails/Model/Serialize.lua`
- Test: `spec/serialize_spec.lua`

**Interfaces:**
- Consumes: `Util.isArray`, `Util.sortedKeys`, `Util.round4`, `Util.trim`, `Util.deepCopy`.
- Produces: `Serialize.clean(d)` → copy with only `id, name, art, rooms, bosses, routes`, positions rounded; `Serialize.dungeon(d)` → text; `Serialize.parse(text)` → dungeon or `nil, err`; `Serialize.validate(d)` → `true` or `false, err`.

- [ ] **Step 1: Write the failing tests**

`spec/serialize_spec.lua`:
```lua
local Serialize = require("Model.Serialize")

local D = { id = 36, name = "The Deadmines",
  art = { kind = "native", floors = { { name = "Mines", uiMapID = 291 }, { name = "Ironclad Cove", uiMapID = 292 } } },
  rooms = { ["The Deadmines"] = { floor = 1, x = 0.12, y = 0.8 }, ["Goblin Foundry"] = { seenAt = 1791850300 },
            ["Ironclad Cove"] = { floor = 2, x = 0.5, y = 0.5 } },
  bosses = { ["Rhahk'Zor"] = { room = "The Deadmines" }, ["Mr. Smite"] = { room = "Ironclad Cove", floor = 2, x = 0.45, y = 0.62 } },
  routes = { { name = "Standard", steps = {
    { room = "The Deadmines", note = "Pull the \"first\" two packs\nback to the tunnel" }, { boss = "Rhahk'Zor" } } } },
  activeRoute = "Standard" }

describe("Serialize", function()
  it("round-trips a dungeon, dropping activeRoute and rounding positions", function()
    local d = require("Core.Util").deepCopy(D)
    d.rooms["The Deadmines"].x = 0.123456
    local text = Serialize.dungeon(d)
    local back, err = Serialize.parse(text)
    assert.is_nil(err)
    assert.is_nil(back.activeRoute)
    assert.are.equal(0.1235, back.rooms["The Deadmines"].x)
    back.rooms["The Deadmines"].x = 0.12
    assert.are.same(Serialize.clean(D), back)
  end)

  it("is deterministic with sorted keys", function()
    local text = Serialize.dungeon(D)
    assert.are.equal(text, Serialize.dungeon(D))
    assert.truthy(text:find("^TankTrails_RegisterDungeon%({\n  art = {"))
    assert.truthy(text:find('%["Goblin Foundry"%] = {\n      seenAt = 1791850300,'))
    assert.truthy(text:find("id = 36,\n  name = \"The Deadmines\","))
  end)

  it("rejects text that calls a global", function()
    local d, err = Serialize.parse('print(1) TankTrails_RegisterDungeon({ id = 1, name = "x" })')
    assert.is_nil(d)
    assert.truthy(err:find("Import failed"))
  end)

  it("rejects zero or two registrations, non-Lua and empty text", function()
    local _, err = Serialize.parse("local x = 1")
    assert.truthy(err:find("exactly one"))
    _, err = Serialize.parse('TankTrails_RegisterDungeon({ id = 1, name = "a" }) TankTrails_RegisterDungeon({ id = 2, name = "b" })')
    assert.truthy(err:find("found 2"))
    _, err = Serialize.parse("this is not lua {")
    assert.truthy(err:find("Not valid Lua"))
    _, err = Serialize.parse("   ")
    assert.are.equal("Nothing to import", err)
  end)

  it("validates shape: id, name, step keys, positions", function()
    assert.is_false(Serialize.validate({ name = "x" }))
    assert.is_false(Serialize.validate({ id = 1 }))
    local _, err = Serialize.validate({ id = 1, name = "x", routes = { { name = "r", steps = { { room = "A", boss = "B" } } } } })
    assert.truthy(err:find("exactly one of room or boss"))
    _, err = Serialize.validate({ id = 1, name = "x", rooms = { A = { floor = 1, x = 1.2, y = 0 } } })
    assert.truthy(err:find("between 0 and 1"))
    _, err = Serialize.validate({ id = 1, name = "x", routes = { { steps = {} } } })
    assert.truthy(err:find("route name"))
    assert.is_true(Serialize.validate(D))
  end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted spec/serialize_spec.lua`
Expected: `module 'Model.Serialize' not found`.

- [ ] **Step 3: Write Serialize**

`TankTrails/Model/Serialize.lua`:
```lua
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
  for _, k in ipairs({ "x", "y" }) do
    local v = rec[k]
    if v ~= nil and (type(v) ~= "number" or v < 0 or v > 1) then
      return false, where .. ": " .. k .. " must be between 0 and 1"
    end
  end
  return true
end

function Serialize.validate(d)
  if type(d) ~= "table" then return false, "not a table" end
  if type(d.id) ~= "number" then return false, "id must be a number" end
  if type(d.name) ~= "string" then return false, "name must be a string" end
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
    if type(route.name) ~= "string" then return false, "route " .. i .. " has no route name" end
    for j, step in ipairs(route.steps or {}) do
      local n = (step.room and 1 or 0) + (step.boss and 1 or 0)
      if n ~= 1 then return false, "route " .. route.name .. " step " .. j .. " needs exactly one of room or boss" end
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
  local vok, verr = Serialize.validate(got)
  if not vok then return nil, verr end
  return Serialize.clean(got)
end

return Serialize
```

- [ ] **Step 4: Run them to verify they pass**

Run: `.lua/bin/busted spec/serialize_spec.lua`
Expected: `5 successes`.

- [ ] **Step 5: Commit**

```bash
git add spec/serialize_spec.lua TankTrails/Model/Serialize.lua
git commit -m "Add Model/Serialize: export text, sandboxed import, validation"
```

---

### Task 9: Model/Geometry

**Files:**
- Create: `TankTrails/Model/Geometry.lua`
- Test: `spec/geometry_spec.lua`

**Interfaces:**
- Produces: `Geometry.bearing(a, b)` → radians clockwise from screen-up in image space (y down), 0 for the same point; `Geometry.grid(layerWidth, layerHeight, tileWidth, tileHeight)` → `cols, rows`; `Geometry.fit(imageW, imageH, boxW, boxH)` → `{ x, y, w, h }` centered in the box; `Geometry.toImage(px, py, rect)` → `x, y` in 0..1 or nil outside.

- [ ] **Step 1: Write the failing tests**

`spec/geometry_spec.lua`:
```lua
local G = require("Model.Geometry")
local function near(a, b) return math.abs(a - b) < 1e-9 end

describe("Geometry", function()
  it("bearing is clockwise from up", function()
    local o = { x = 0.5, y = 0.5 }
    assert.is_true(near(0, G.bearing(o, { x = 0.5, y = 0.1 })))
    assert.is_true(near(math.pi / 2, G.bearing(o, { x = 0.9, y = 0.5 })))
    assert.is_true(near(math.pi, G.bearing(o, { x = 0.5, y = 0.9 })))
    assert.is_true(near(-math.pi / 2, G.bearing(o, { x = 0.1, y = 0.5 })))
    assert.is_true(near(math.pi / 4, G.bearing(o, { x = 0.6, y = 0.4 })))
    assert.are.equal(0, G.bearing(o, o))
  end)

  it("grid rounds up partial tiles", function()
    local cols, rows = G.grid(1002, 668, 256, 256)
    assert.are.equal(4, cols)
    assert.are.equal(3, rows)
  end)

  it("fit letterboxes wide and tall images", function()
    assert.are.same({ x = 0, y = 100, w = 800, h = 400 }, G.fit(1000, 500, 800, 600))
    assert.are.same({ x = 250, y = 0, w = 300, h = 600 }, G.fit(500, 1000, 800, 600))
  end)

  it("toImage maps canvas pixels into 0..1 and rejects outside", function()
    local rect = { x = 0, y = 100, w = 800, h = 400 }
    local x, y = G.toImage(400, 300, rect)
    assert.is_true(near(0.5, x) and near(0.5, y))
    assert.is_nil(G.toImage(400, 50, rect))
  end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted spec/geometry_spec.lua`
Expected: `module 'Model.Geometry' not found`.

- [ ] **Step 3: Write Geometry**

`TankTrails/Model/Geometry.lua`:
```lua
local _, ns = ...
ns = ns or {}

local Geometry = {}
ns.Geometry = Geometry

-- Radians clockwise from screen-up, in image space where y grows downwards (spec §7.1).
function Geometry.bearing(a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  if dx == 0 and dy == 0 then return 0 end
  return math.atan2(dx, -dy)
end

function Geometry.grid(layerWidth, layerHeight, tileWidth, tileHeight)
  return math.ceil(layerWidth / tileWidth), math.ceil(layerHeight / tileHeight)
end

-- The largest rectangle with the image's aspect that fits the box, centered.
function Geometry.fit(imageW, imageH, boxW, boxH)
  local scale = math.min(boxW / imageW, boxH / imageH)
  local w, h = imageW * scale, imageH * scale
  return { x = (boxW - w) / 2, y = (boxH - h) / 2, w = w, h = h }
end

function Geometry.toImage(px, py, rect)
  local x, y = (px - rect.x) / rect.w, (py - rect.y) / rect.h
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return x, y
end

return Geometry
```

- [ ] **Step 4: Run them to verify they pass**

Run: `.lua/bin/busted spec/geometry_spec.lua`
Expected: `4 successes`.

- [ ] **Step 5: Commit**

```bash
git add spec/geometry_spec.lua TankTrails/Model/Geometry.lua
git commit -m "Add Model/Geometry: bearing, grid, fit"
```

---

### Task 10: Wow/Store (SavedVariables access)

**Files:**
- Create: `TankTrails/Wow/Store.lua`
- Test: `spec/store_spec.lua`

**Interfaces:**
- Consumes: `Merge.effective`, `Util.deepCopy`, `Util.round4`, `Util.trim`.
- Produces: `Store.new(accountDb, charDb, shipped)` → store with
  - `:effective(id, name)` → effective dungeon; `:overlay(id)` → saved overlay table (created on demand);
  - `:run()` / `:setRun(run)` (character); `:fileRun(run)` (newest first, cap 5); `:lastRun(id)`;
  - `:seenRoom(id, key, now)`; `:placeRoom(id, key, floor, x, y)`; `:placeBoss(id, key, floor, x, y)`; `:learnBoss(id, key, info)`;
  - `:setRoute(id, route)` (replace by name or append, makes it active); `:setActiveRoute(id, name)`; `:editableRoute(id, name)` → overlay copy of that route; `:setNote(id, routeName, index, text)` (empty clears);
  - `:replaceOverlay(id, dungeon)` (import); `:reset(id)`; `:settings()`.
- The `accountDb` and `charDb` tables are the SavedVariables themselves after `Init.applyDefaults`, so every write persists.

- [ ] **Step 1: Write the failing tests**

`spec/store_spec.lua`:
```lua
local Store = require("Wow.Store")
local Init = require("Core.Init")

local SHIPPED = { [36] = { id = 36, name = "The Deadmines",
  rooms = { ["Mast Room"] = { floor = 1, x = 0.4, y = 0.6 } },
  bosses = { ["Sneed"] = { room = "Mast Room" } },
  routes = { { name = "Standard", steps = { { room = "Mast Room", note = "shipped note" }, { boss = "Sneed" } } } } } }

local function store()
  local account, char = Init.applyDefaults({}, Init.ACCOUNT_DEFAULTS), Init.applyDefaults({}, Init.CHAR_DEFAULTS)
  return Store.new(account, char, SHIPPED), account, char
end

describe("Store", function()
  it("merges shipped and overlay into the effective dungeon", function()
    local s = store()
    assert.are.equal("Standard", s:effective(36, "x").routes[1].name)
    assert.are.same({ id = 7, name = "Cave", rooms = {}, bosses = {}, routes = {} }, s:effective(7, "Cave"))
  end)

  it("keeps the character run and files runs newest first, capped at five", function()
    local s, account, char = store()
    assert.is_nil(s:run())
    s:setRun({ dungeon = 36, startedAt = 1 })
    assert.are.equal(1, char.run.startedAt)
    for i = 1, 6 do s:fileRun({ dungeon = 36, startedAt = i, endedAt = i + 1 }) end
    assert.are.equal(5, #account.runs[36])
    assert.are.equal(6, account.runs[36][1].startedAt)
    assert.are.equal(6, s:lastRun(36).startedAt)
    assert.is_nil(s:lastRun(99))
  end)

  it("records a seen room only when neither shipped nor saved know it", function()
    local s, account = store()
    s:seenRoom(36, "Mast Room", 100)
    assert.is_nil(account.dungeons[36].rooms["Mast Room"])
    s:seenRoom(36, "Goblin Foundry", 100)
    assert.are.same({ seenAt = 100 }, account.dungeons[36].rooms["Goblin Foundry"])
    s:seenRoom(36, "Goblin Foundry", 200)
    assert.are.equal(100, account.dungeons[36].rooms["Goblin Foundry"].seenAt)
  end)

  it("places rooms and bosses, rounding and keeping shipped fields", function()
    local s, account = store()
    s:placeRoom(36, "Mast Room", 1, 0.123456, 0.5)
    assert.are.same({ floor = 1, x = 0.1235, y = 0.5 }, account.dungeons[36].rooms["Mast Room"])
    s:placeBoss(36, "Sneed", 1, 0.2, 0.3)
    assert.are.same({ room = "Mast Room", floor = 1, x = 0.2, y = 0.3 }, account.dungeons[36].bosses["Sneed"])
    s:learnBoss(36, "Sneed", { room = "Mast Room", encounterID = 5 })
    assert.are.equal(5, account.dungeons[36].bosses["Sneed"].encounterID)
    assert.are.equal(0.2, account.dungeons[36].bosses["Sneed"].x)
    s:learnBoss(36, "Cookie", { room = "Ironclad Cove" })
    assert.are.same({ room = "Ironclad Cove" }, account.dungeons[36].bosses["Cookie"])
  end)

  it("sets routes by name, makes them active, and edits notes copy-on-write", function()
    local s, account = store()
    s:setRoute(36, { name = "Recorded", steps = { { room = "A" } } })
    assert.are.equal("Recorded", account.dungeons[36].activeRoute)
    s:setRoute(36, { name = "Recorded", steps = { { room = "B" } } })
    assert.are.equal(1, #account.dungeons[36].routes)
    assert.are.equal("B", account.dungeons[36].routes[1].steps[1].room)
    s:setActiveRoute(36, "Standard")
    assert.are.equal("Standard", account.dungeons[36].activeRoute)
    local r = s:editableRoute(36, "Standard")
    assert.are.equal("shipped note", r.steps[1].note)
    assert.are.equal(2, #account.dungeons[36].routes)
    s:setNote(36, "Standard", 1, "my note")
    assert.are.equal("my note", s:effective(36, "x").routes[1].steps[1].note)
    assert.are.equal("shipped note", SHIPPED[36].routes[1].steps[1].note)
    s:setNote(36, "Standard", 1, "   ")
    assert.is_nil(s:effective(36, "x").routes[1].steps[1].note)
    assert.is_nil(s:editableRoute(36, "Nope"))
  end)

  it("replaces the overlay on import and wipes it on reset", function()
    local s, account = store()
    s:setRoute(36, { name = "Recorded", steps = {} })
    s:replaceOverlay(36, { id = 36, name = "Deadmines (beta)", rooms = { A = {} }, bosses = {}, routes = { { name = "Imported", steps = {} } } })
    local d = s:effective(36, "x")
    assert.are.equal("Deadmines (beta)", d.name)
    assert.are.equal("Imported", d.activeRoute)
    assert.are.equal(2, #d.routes)
    s:reset(36)
    assert.is_nil(account.dungeons[36])
    assert.is_true(s:settings().autoOpen)
  end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted spec/store_spec.lua`
Expected: `module 'Wow.Store' not found`.

- [ ] **Step 3: Write Store**

`TankTrails/Wow/Store.lua`:
```lua
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
  if shippedRecord(self, id, "rooms", key) then return end
  local o = self:overlay(id)
  o.rooms = o.rooms or {}
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
```

- [ ] **Step 4: Run them to verify they pass**

Run: `.lua/bin/busted spec/store_spec.lua`
Expected: `6 successes`.

- [ ] **Step 5: Commit**

```bash
git add spec/store_spec.lua TankTrails/Wow/Store.lua
git commit -m "Add Wow/Store: SavedVariables access"
```

---

### Task 11: Wow/Events (event frame to handler calls)

**Files:**
- Create: `TankTrails/Wow/Events.lua`
- Test: `spec/events_spec.lua`

**Interfaces:**
- Consumes: `Safe.*`, `fake_env.frame` (tests).
- Produces: `Events.create(env, handlers, trap)` → events object, where the optional `trap(label, fn)` (App passes `Util.wrap` bound to its error log) wraps the whole dispatch so an error anywhere in a handler or in a payload read is logged, not raised; `Events.LIST`; `:zoneText()` → safe minimap zone text or nil; `:targetName()` → safe name of a non-player target or nil; `:dispatch(event, ...)`; `:stop()`.
- `handlers`: `world()`, `zone(text, newArea)`, `boss(encounterID, name, success)`, `combatStart()`, `combatEnd()`, `dead()`, `target(name)`.

- [ ] **Step 1: Write the failing tests**

`spec/events_spec.lua`:
```lua
local fake = require("helpers.fake_env")
local Events = require("Wow.Events")

local function harness(state)
  local env, st = fake.new(state)
  local calls = {}
  local function rec(name) return function(...) table.insert(calls, { name, ... }) end end
  local handlers = { world = rec("world"), zone = rec("zone"), boss = rec("boss"), combatStart = rec("combatStart"),
    combatEnd = rec("combatEnd"), dead = rec("dead"), target = rec("target") }
  local ev = Events.create(env, handlers)
  return ev, ev.frame, calls, st
end

describe("Events", function()
  it("registers every event in LIST", function()
    local _, frame = harness()
    for _, e in ipairs(Events.LIST) do assert.is_true(frame.events[e], e) end
    assert.are.equal(10, #Events.LIST)
  end)

  it("maps zone events to the safe zone text and flags new areas", function()
    local _, frame, calls, st = harness({ zoneText = "Mast Room" })
    frame:fire("ZONE_CHANGED")
    assert.are.same({ "zone", "Mast Room", false }, calls[1])
    frame:fire("ZONE_CHANGED_NEW_AREA")
    assert.are.same({ "zone", "Mast Room", true }, calls[2])
    st.zoneText = ""
    frame:fire("ZONE_CHANGED_INDOORS")
    assert.are.same({ "zone", nil, false }, calls[3])
  end)

  it("maps encounter and boss-kill events, stripping secrets", function()
    local _, frame, calls, st = harness()
    frame:fire("ENCOUNTER_END", 1234, "Rhahk'Zor", 1, 5, 1)
    assert.are.same({ "boss", 1234, "Rhahk'Zor", true }, calls[1])
    frame:fire("ENCOUNTER_END", 1234, "Rhahk'Zor", 1, 5, 0)
    assert.are.same({ "boss", 1234, "Rhahk'Zor", false }, calls[2])
    st.secrets["Sneed"] = true
    frame:fire("BOSS_KILL", 4321, "Sneed")
    assert.are.same({ "boss", 4321, nil, true }, calls[3])
  end)

  it("maps combat, death and world events", function()
    local _, frame, calls = harness()
    frame:fire("PLAYER_REGEN_DISABLED"); frame:fire("PLAYER_REGEN_ENABLED"); frame:fire("PLAYER_DEAD"); frame:fire("PLAYER_ENTERING_WORLD")
    assert.are.same({ { "combatStart" }, { "combatEnd" }, { "dead" }, { "world" } }, calls)
  end)

  it("reports a non-player target's name, nil for players, secrets and no target", function()
    local _, frame, calls, st = harness({ target = { name = "Defias Miner" } })
    frame:fire("PLAYER_TARGET_CHANGED")
    assert.are.same({ "target", "Defias Miner" }, calls[1])
    st.target = { name = "Bob", isPlayer = true }
    frame:fire("PLAYER_TARGET_CHANGED")
    assert.are.same({ "target" }, calls[2])
    st.target = { name = "Defias Miner" }
    st.secrets["Defias Miner"] = true
    frame:fire("PLAYER_TARGET_CHANGED")
    assert.are.same({ "target" }, calls[3])
    st.target = nil
    frame:fire("PLAYER_TARGET_CHANGED")
    assert.are.same({ "target" }, calls[4])
  end)

  it("skips the target when UnitIsPlayer itself is secret, and stops cleanly", function()
    local ev, frame, calls, st = harness({ target = { name = "Defias Miner" } })
    st.secrets[false] = true
    frame:fire("PLAYER_TARGET_CHANGED")
    assert.are.same({ "target" }, calls[1])
    ev:stop()
    assert.are.same({}, frame.events)
  end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted spec/events_spec.lua`
Expected: `module 'Wow.Events' not found`.

- [ ] **Step 3: Write Events**

`TankTrails/Wow/Events.lua`:
```lua
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
```

- [ ] **Step 4: Run them to verify they pass**

Run: `.lua/bin/busted spec/events_spec.lua`
Expected: `6 successes`.

- [ ] **Step 5: Commit**

```bash
git add spec/events_spec.lua TankTrails/Wow/Events.lua
git commit -m "Add Wow/Events: game events to safe handler calls"
```

---

### Task 12: Core/App (run lifecycle, replay, view, actions)

**Files:**
- Create: `TankTrails/Core/App.lua`
- Test: `spec/app_spec.lua`

**Interfaces:**
- Consumes: everything from Tasks 1–11.
- Produces: `App.new(deps)` where `deps = { env, store, ui = { hud = function(hudSettings, onClick) -> hud } or nil, now = fn or nil }`; `App.PREFIX`.
  - `:start()` → true; `:print(msg)`; `:refresh()` → view; `:view()` → view table (below).
  - Handlers: `:onWorld()`, `:onZone(text, newArea)`, `:onBoss(id, name, success)`, `:onCombat(started)`, `:onDead()`, `:onTarget(name)`, `:onTick()`.
  - Actions for commands: `:note(text)` → ok, msg; `:tickBoss(name)` → ok, msg; `:promote(name, force)` → `"confirm"` | ok, msg; `:switchRoute(name)` → ok, msg; `:exportText()` → text or nil, msg; `:importText(text, force)` → `"confirm", name` | ok, msg; `:debugLines()` → array of strings; `:reset(force)` → `"confirm"` | ok, msg; `:setAutoOpen(on)`; `:setScale(n)`; `:toggleHud()`; `:lockHud()`.
  - `hud` object contract (Task 14): `:update(view)`, `:toggle()`, `:setLocked(bool)`, `:setScale(n)`.
- View table: `{ mode = "none" | "learning" | "route", dungeonName, currentRoom, runSeconds, counts = { rooms, bosses } (learning), routeName, offRoute, done, total, note, next, nextKind = "room" | "boss", nextNote, bearing, floorHint = "up" | "down", floorName, complete, unexpected }`.

- [ ] **Step 1: Write the failing tests**

`spec/app_spec.lua`:
```lua
local fake = require("helpers.fake_env")
local Init = require("Core.Init")
local Store = require("Wow.Store")
local App = require("Core.App")

local DEADMINES = { id = 36, name = "The Deadmines",
  rooms = { ["The Deadmines"] = { floor = 1, x = 0.5, y = 0.9 }, ["Mast Room"] = { floor = 1, x = 0.5, y = 0.5 },
            ["Ironclad Cove"] = { floor = 2, x = 0.5, y = 0.5 } },
  bosses = { ["Rhahk'Zor"] = { room = "The Deadmines" } },
  routes = { { name = "Standard", steps = {
    { room = "The Deadmines", note = "first packs" }, { boss = "Rhahk'Zor" }, { room = "Mast Room", note = "ramp" },
    { boss = "Sneed" }, { room = "Ironclad Cove" }, { boss = "Mr. Smite" } } } } }

local function hudFactory(log)
  return function(settings, onClick)
    local hud = { settings = settings, onClick = onClick, updates = log, shown = true, locked = false, scale = 1 }
    function hud:update(view) table.insert(self.updates, view) end
    function hud:toggle() self.shown = not self.shown end
    function hud:setLocked(b) self.locked = b end
    function hud:setScale(n) self.scale = n end
    return hud
  end
end

local function boot(state, shipped, dbs)
  local env, st = fake.new(state)
  env.date = function(fmt, t) return "2026-10-12" end
  local account = dbs and dbs.account or Init.applyDefaults({}, Init.ACCOUNT_DEFAULTS)
  local char = dbs and dbs.char or Init.applyDefaults({}, Init.CHAR_DEFAULTS)
  local store = Store.new(account, char, shipped or {})
  local updates = {}
  local app = App.new({ env = env, store = store, ui = { hud = hudFactory(updates) } })
  app:start()
  local frame = app.events.frame
  return app, frame, st, updates, { account = account, char = char }
end

local function lastView(updates) return updates[#updates] end

describe("App lifecycle", function()
  it("opens the run on the first event that has instance info", function()
    local app, frame, st = boot({ now = 1000 })
    assert.is_nil(app.run)
    st.instance = { name = "The Deadmines", id = 36 }
    st.zoneText = "The Deadmines"
    st.now = 1001
    frame:fire("ZONE_CHANGED_NEW_AREA")
    assert.are.equal(36, app.run.dungeon)
    assert.are.equal("The Deadmines", app.run.events[1].room)
  end)

  it("retries from the ticker when zone events never came", function()
    local app, _, st = boot({ now = 1000 })
    st.instance = { name = "The Deadmines", id = 36 }
    st.zoneText = "The Deadmines"
    st.ticker()
    assert.are.equal(36, app.run.dungeon)
  end)

  it("resumes the saved run after a reload", function()
    local app, frame, st, _, dbs = boot({ now = 1000, instance = { name = "The Deadmines", id = 36 }, zoneText = "The Deadmines" })
    st.now, st.zoneText = 1030, "Mast Room"
    frame:fire("ZONE_CHANGED")
    assert.are.equal(2, #dbs.char.run.events)
    local app2 = boot({ now = 1031, instance = { name = "The Deadmines", id = 36 }, zoneText = "Mast Room" }, nil, dbs)
    assert.are.equal(dbs.char.run, app2.run)
    assert.are.equal(2, #app2.run.events)
  end)

  it("closes and files the run on leaving, and tells the player", function()
    local app, frame, st, _, dbs = boot({ now = 1000, instance = { name = "The Deadmines", id = 36 }, zoneText = "The Deadmines" })
    st.instance, st.zoneText, st.now = nil, "Westfall", 1500
    frame:fire("PLAYER_ENTERING_WORLD")
    assert.is_nil(app.run)
    assert.is_nil(dbs.char.run)
    assert.are.equal(1500, dbs.account.runs[36][1].endedAt)
    assert.truthy(st.chat[#st.chat]:find("promote"))
  end)
end)

describe("App view", function()
  it("shows learning mode with counts when the dungeon has no route", function()
    local app, frame, st, updates = boot({ now = 1000, instance = { name = "Cave", id = 7 }, zoneText = "Cave" })
    st.zoneText = "Deep Cave"; frame:fire("ZONE_CHANGED")
    frame:fire("ENCOUNTER_END", 9, "Bat", 1, 5, 1)
    local v = lastView(updates)
    assert.are.equal("learning", v.mode)
    assert.are.equal("Deep Cave", v.currentRoom)
    assert.are.same({ rooms = 2, bosses = 1 }, v.counts)
  end)

  it("follows a shipped route: next step, notes, progress, bearing, floor hint", function()
    local app, frame, st, updates = boot({ now = 1000, instance = { name = "The Deadmines", id = 36 }, zoneText = "The Deadmines" }, { [36] = DEADMINES })
    local v = lastView(updates)
    assert.are.equal("route", v.mode)
    assert.are.equal("Standard", v.routeName)
    assert.are.equal("first packs", v.note)
    assert.are.equal("Rhahk'Zor", v.next)
    assert.are.equal("boss", v.nextKind)
    assert.are.equal(0, v.bearing)              -- boss drawn at its room, same spot
    frame:fire("ENCOUNTER_END", 1234, "Rhahk'Zor", 1, 5, 1)
    v = lastView(updates)
    assert.are.equal(1, v.done); assert.are.equal(3, v.total)
    assert.are.equal("Mast Room", v.next)
    assert.is_true(math.abs(v.bearing) < 1e-9)  -- straight up from y 0.9 to y 0.5
    assert.are.equal(1234, app.dungeon.bosses["Rhahk'Zor"].encounterID)
    st.zoneText = "Mast Room"; frame:fire("ZONE_CHANGED")
    v = lastView(updates)
    assert.are.equal("Sneed", v.next)
    assert.are.equal("ramp", v.note)
    frame:fire("BOSS_KILL", 5, "Sneed")
    v = lastView(updates)
    assert.are.equal("Ironclad Cove", v.next)
    assert.is_nil(v.bearing)
    assert.are.equal("up", v.floorHint)
    st.zoneText = "Secret Cave"; frame:fire("ZONE_CHANGED")
    assert.are.equal("Secret Cave", lastView(updates).offRoute)
  end)
end)

describe("App actions", function()
  it("notes go to the run in learning mode and to the step in route mode", function()
    local app, frame, st, updates, dbs = boot({ now = 1000, instance = { name = "Cave", id = 7 }, zoneText = "Cave" })
    assert.is_true((app:note("pull back")))
    assert.are.equal("note", app.run.events[2].kind)
    local app2, _, _, updates2, dbs2 = boot({ now = 1000, instance = { name = "The Deadmines", id = 36 }, zoneText = "The Deadmines" }, { [36] = DEADMINES })
    assert.is_true((app2:note("my note")))
    assert.are.equal("my note", lastView(updates2).note)
    assert.are.equal("my note", dbs2.account.dungeons[36].routes[1].steps[1].note)
    local ok, msg = app2:note("")
    assert.is_true(ok)
  end)

  it("tickBoss ticks the next undone boss, or a named one in learning mode", function()
    local app, _, _, updates = boot({ now = 1000, instance = { name = "The Deadmines", id = 36 }, zoneText = "The Deadmines" }, { [36] = DEADMINES })
    assert.is_true((app:tickBoss()))
    assert.are.equal("Rhahk'Zor", app.run.events[#app.run.events].name)
    assert.is_true(app.run.events[#app.run.events].manual)
    assert.are.equal(1, lastView(updates).done)
    local app2 = boot({ now = 1000, instance = { name = "Cave", id = 7 }, zoneText = "Cave" })
    local ok, msg = app2:tickBoss()
    assert.is_false(ok)
    assert.is_true((app2:tickBoss("Bat")))
  end)

  it("promote after leaving creates and activates the route; same name asks to confirm", function()
    local app, frame, st, updates, dbs = boot({ now = 1000, instance = { name = "Cave", id = 7 }, zoneText = "Cave" })
    st.zoneText, st.now = "Deep Cave", 1100; frame:fire("ZONE_CHANGED")
    frame:fire("ENCOUNTER_END", 9, "Bat", 1, 5, 1)
    st.instance, st.zoneText, st.now = nil, "Barrens", 1200; frame:fire("PLAYER_ENTERING_WORLD")
    assert.is_true((app:promote()))
    local saved = dbs.account.dungeons[7]
    assert.are.equal("Recorded 2026-10-12", saved.activeRoute)
    assert.are.same({ { room = "Cave" }, { room = "Deep Cave" }, { boss = "Bat" } }, saved.routes[1].steps)
    assert.are.equal(9, saved.bosses["Bat"].encounterID)
    assert.are.equal("confirm", app:promote())
    assert.is_true((app:promote(nil, true)))
    local ok, msg = boot({ now = 1 }):promote()
    assert.is_false(ok)
  end)

  it("switches routes by name and lists them when unknown", function()
    local two = { id = 36, name = "The Deadmines", routes = { { name = "A", steps = { { room = "The Deadmines" } } }, { name = "B", steps = { { room = "The Deadmines" } } } } }
    local app, _, _, updates = boot({ now = 1000, instance = { name = "The Deadmines", id = 36 }, zoneText = "The Deadmines" }, { [36] = two })
    assert.is_true((app:switchRoute("B")))
    assert.are.equal("B", lastView(updates).routeName)
    local ok, msg = app:switchRoute("C")
    assert.is_false(ok)
    assert.truthy(msg:find("A, B"))
  end)

  it("exports and imports the current dungeon", function()
    local app, _, _, updates, dbs = boot({ now = 1000, instance = { name = "The Deadmines", id = 36 }, zoneText = "The Deadmines" }, { [36] = DEADMINES })
    local text = app:exportText()
    assert.truthy(text:find("TankTrails_RegisterDungeon"))
    local edited = text:gsub('note = "ramp"', 'note = "patrol on the ramp"')
    assert.are.equal("confirm", app:importText(edited))
    assert.is_true((app:importText(edited, true)))
    assert.are.equal("patrol on the ramp", dbs.account.dungeons[36].routes[1].steps[3].note)
    local ok, msg = app:importText("print(1)")
    assert.is_false(ok)
    assert.truthy(msg:find("Import failed"))
  end)

  it("reset asks to confirm, then wipes the overlay; debug lists state; errors are trapped", function()
    local app, frame, st, updates, dbs = boot({ now = 1000, instance = { name = "The Deadmines", id = 36 }, zoneText = "The Deadmines" }, { [36] = DEADMINES })
    app:note("x")
    assert.are.equal("confirm", app:reset())
    assert.is_true((app:reset(true)))
    assert.is_nil(dbs.account.dungeons[36])
    local lines = app:debugLines()
    assert.truthy(table.concat(lines, "\n"):find("dungeon 36"))
    local env = app.env
    env.GetMinimapZoneText = function() error("boom") end
    frame:fire("ZONE_CHANGED")
    assert.are.equal(1, #app.errors.entries)
  end)

  it("settings reach the hud", function()
    local app, _, _, _, dbs = boot({ now = 1 })
    app:setScale(1.5); app:toggleHud(); app:lockHud(); app:setAutoOpen(false)
    assert.are.equal(1.5, dbs.account.settings.hud.scale)
    assert.is_false(app.hud.shown)
    assert.is_true(dbs.account.settings.hud.locked)
    assert.is_false(dbs.account.settings.autoOpen)
  end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted spec/app_spec.lua`
Expected: `module 'Core.App' not found`.

- [ ] **Step 3: Write App**

`TankTrails/Core/App.lua`:
```lua
local _, ns = ...
ns = ns or {}
local function dep(name, path) return ns[name] or require(path) end
local Util = dep("Util", "Core.Util")
local Recorder = dep("Recorder", "Model.Recorder")
local Route = dep("Route", "Model.Route")
local Promote = dep("Promote", "Model.Promote")
local Serialize = dep("Serialize", "Model.Serialize")
local Geometry = dep("Geometry", "Model.Geometry")
local InstanceWatch = dep("InstanceWatch", "Wow.InstanceWatch")
local Events = dep("Events", "Wow.Events")

local App = {}
App.__index = App
ns.App = App
App.PREFIX = "|cff4fd18bTankTrails:|r "

function App.new(deps)
  local self = setmetatable({ deps = deps, env = deps.env, store = deps.store, errors = Util.newErrorLog() }, App)
  self.now = deps.now or function() return deps.env.time() end
  return self
end

function App:print(msg)
  local chat = self.env.DEFAULT_CHAT_FRAME
  if chat then chat:AddMessage(App.PREFIX .. tostring(msg)) end
end

function App:start()
  local function wrap(label, fn) return Util.wrap(self.errors, label, fn) end
  self.events = Events.create(self.env, {
    world = wrap("world", function() self:onWorld() end),
    zone = wrap("zone", function(text, newArea) self:onZone(text, newArea) end),
    boss = wrap("boss", function(id, name, ok) self:onBoss(id, name, ok) end),
    combatStart = wrap("combatStart", function() self:onCombat(true) end),
    combatEnd = wrap("combatEnd", function() self:onCombat(false) end),
    dead = wrap("dead", function() self:onDead() end),
    target = wrap("target", function(name) self:onTarget(name) end),
  }, wrap)
  local ui = self.deps.ui
  if ui and ui.hud then
    self.hud = ui.hud(self.store:settings().hud, function() self:toggleMap() end)
  end
  self.ticker = self.env.C_Timer.NewTicker(1, wrap("tick", function() self:onTick() end))
  self:onWorld()
  return true
end

-- The map arrives in the next plan; keep the hook so the HUD click has somewhere to go.
function App:toggleMap()
  if self.deps.ui and self.deps.ui.toggleMap then self.deps.ui.toggleMap() else self:print("The map is not built yet.") end
end

-- Spec §6.1
function App:onWorld()
  local id, name = InstanceWatch.current(self.env)
  local saved = self.store:run()
  if id then
    local run, stale = Recorder.open(saved, id, name, self.now())
    if stale then self.store:fileRun(stale) end
    self.store:setRun(run)
    self.run, self.dungeon = run, self.store:effective(id, name)
    self:onZone(self.events:zoneText(), false)
  else
    if saved and not saved.endedAt then
      Recorder.close(saved, self.now())
      self.store:fileRun(saved)
      self.store:setRun(nil)
      self.last = { id = saved.dungeon, name = saved.name }
      self:print("Run in " .. tostring(saved.name) .. " recorded. /tt promote turns it into a route.")
    end
    self.run, self.dungeon = nil, nil
  end
  self:refresh()
end

function App:onZone(text, newArea)
  if not self.run then
    if newArea then self:onWorld() end
    return
  end
  if newArea and InstanceWatch.current(self.env) ~= self.run.dungeon then return self:onWorld() end
  local ev = Recorder.room(self.run, text, self.now())
  if ev then self.store:seenRoom(self.run.dungeon, ev.room, self.now()) end
  self:refresh()
end

function App:onTick()
  if not self.run then
    if InstanceWatch.current(self.env) then self:onWorld() end
    return
  end
  self:onZone(self.events:zoneText(), false)
end

local function bossKey(ev) return ev.name or ("#" .. tostring(ev.encounterID)) end

function App:onBoss(id, name, success)
  if not self.run or not success then return end
  local ev = Recorder.boss(self.run, name, id, self.now())
  if not ev then return end
  self.store:learnBoss(self.run.dungeon, bossKey(ev), { room = ev.room, encounterID = ev.encounterID })
  self.dungeon = self.store:effective(self.run.dungeon, self.run.name)
  self:refresh()
end

function App:onCombat(started)
  if not self.run then return end
  if started then Recorder.pullStart(self.run, self.now()) else Recorder.pullEnd(self.run, self.now()) end
end

function App:onDead() if self.run then Recorder.death(self.run) end end
function App:onTarget(name) if self.run then Recorder.target(self.run, name, self.now()) end end

-- Where a step sits on the map: a room's own position; a boss's own, else its room's (spec §5.1).
local function position(d, step)
  if step.room then
    local r = d.rooms[step.room]
    return r and r.x and r or nil
  end
  local b = d.bosses[step.boss]
  if b and b.x then return b end
  local r = b and b.room and d.rooms[b.room]
  return r and r.x and r or nil
end

function App:view()
  local run, d = self.run, self.dungeon
  if not run or not d then return { mode = "none" } end
  local v = { dungeonName = d.name, currentRoom = Recorder.currentRoom(run), runSeconds = self.now() - run.startedAt }
  local route = Route.select(d, d.activeRoute, run.events)
  self.route = route
  if not route then
    v.mode, v.counts, self.state = "learning", Recorder.counts(run), nil
    return v
  end
  local state = Route.fold(route, run.events, d.bosses)
  self.state = state
  v.mode, v.routeName, v.offRoute, v.unexpected = "route", route.name, state.offRoute, state.unexpected
  v.done, v.total = Route.progress(route, state)
  local cur = route.steps[state.cursor]
  v.note = cur and cur.note or nil
  local j = Route.next(route, state)
  if not j then v.complete = true; return v end
  local nxt = route.steps[j]
  v.next, v.nextKind, v.nextNote = nxt.room or nxt.boss, nxt.room and "room" or "boss", nxt.note
  local a = v.currentRoom and d.rooms[v.currentRoom]
  local b = position(d, nxt)
  if a and a.x and b then
    if a.floor == b.floor then
      v.bearing = Geometry.bearing(a, b)
    else
      v.floorHint = b.floor > a.floor and "up" or "down"
      local floors = d.art and d.art.floors
      v.floorName = floors and floors[b.floor] and floors[b.floor].name or ("floor " .. tostring(b.floor))
    end
  end
  return v
end

function App:refresh()
  local view = self:view()
  if self.hud then self.hud:update(view) end
  return view
end

-- The dungeon commands act on: the one the player is in, else the one they last left this session.
function App:context()
  if self.run then return self.run.dungeon, self.run.name, self.run end
  if self.last then return self.last.id, self.last.name, self.store:lastRun(self.last.id) end
  return nil
end

function App:note(text)
  if not self.run then return false, "Not in a dungeon." end
  local view = self:view()
  if view.mode == "learning" then
    Recorder.note(self.run, Util.trim(text), self.now())
    return true, "Note saved for " .. tostring(view.currentRoom) .. "."
  end
  if self.state.cursor == 0 then return false, "No current step yet." end
  self.store:setNote(self.run.dungeon, self.route.name, self.state.cursor, text)
  self.dungeon = self.store:effective(self.run.dungeon, self.run.name)
  self:refresh()
  return true, "Note saved on step " .. self.state.cursor .. "."
end

function App:tickBoss(name)
  if not self.run then return false, "Not in a dungeon." end
  local view = self:view()
  if not name then
    if view.mode ~= "route" then return false, "No route here. Give the boss a name: /tt boss <name>." end
    local steps, state = self.route.steps, self.state
    for _, start in ipairs({ state.cursor + 1, 1 }) do
      for j = start, #steps do
        if steps[j].boss and not state.done[j] then name = steps[j].boss; break end
      end
      if name then break end
    end
    if not name then return false, "Every boss in the route is done." end
  end
  local ev = Recorder.boss(self.run, name, nil, self.now(), true)
  if not ev then return false, "That boss was just recorded." end
  self.store:learnBoss(self.run.dungeon, name, { room = ev.room })
  self.dungeon = self.store:effective(self.run.dungeon, self.run.name)
  self:refresh()
  return true, "Ticked " .. name .. "."
end

function App:promote(name, force)
  local id, dname, run = self:context()
  if not run then return false, "Enter a dungeon, or finish a run, first." end
  local d = self.store:effective(id, dname)
  local today = self.env.date("%Y-%m-%d", self.now())
  name = name and Util.trim(name) ~= "" and Util.trim(name) or nil
  local target = name or ("Recorded " .. today)
  local old
  for _, r in ipairs(d.routes) do
    if r.name == target then old = r end
  end
  if old and not force then return "confirm" end
  local route, info, err = Promote.run(run, old, target, today, self.now())
  if not route then return false, err end
  self.store:setRoute(id, route)
  for key, rec in pairs(info) do self.store:learnBoss(id, key, rec) end
  if self.run then self.dungeon = self.store:effective(id, dname) end
  self:refresh()
  return true, "Route '" .. route.name .. "' saved with " .. #route.steps .. " steps and set active."
end

function App:switchRoute(name)
  local id, dname = self:context()
  if not id then return false, "Not in a dungeon." end
  local d = self.store:effective(id, dname)
  local names = {}
  for _, r in ipairs(d.routes) do
    names[#names + 1] = r.name
    if r.name == name then
      self.store:setActiveRoute(id, name)
      if self.run then self.dungeon = self.store:effective(id, dname) end
      self:refresh()
      return true, "Active route: " .. name .. "."
    end
  end
  return false, "No route '" .. tostring(name) .. "'. Routes: " .. (#names > 0 and table.concat(names, ", ") or "none") .. "."
end

function App:exportText()
  local id, dname = self:context()
  if not id then return nil, "Not in a dungeon." end
  return Serialize.dungeon(self.store:effective(id, dname))
end

-- Parses first; without force it only reports the dungeon's name so the caller can confirm (spec §5.5).
function App:importText(text, force)
  local d, err = Serialize.parse(text)
  if not d then return false, err end
  if not force then return "confirm", d.name end
  self.store:replaceOverlay(d.id, d)
  if self.run and self.run.dungeon == d.id then
    self.dungeon = self.store:effective(d.id, self.run.name)
    self:refresh()
  end
  return true, "Imported " .. d.name .. " (" .. #d.routes .. " routes)."
end

function App:reset(force)
  local id, dname = self:context()
  if not id then return false, "Not in a dungeon." end
  if not force then return "confirm" end
  self.store:reset(id)
  if self.run then self.dungeon = self.store:effective(id, dname) end
  self:refresh()
  return true, "Saved data for " .. tostring(dname) .. " wiped."
end

function App:debugLines()
  local lines = {}
  local id, dname = self:context()
  lines[#lines + 1] = id and ("dungeon " .. id .. " " .. tostring(dname)) or "no dungeon"
  lines[#lines + 1] = "zone text: " .. tostring(self.events and self.events:zoneText())
  if self.run then
    local v = self:view()
    lines[#lines + 1] = "mode " .. v.mode .. (v.routeName and (", route " .. v.routeName) or "") ..
      (self.state and (", cursor " .. self.state.cursor) or "")
    local n = #self.run.events
    for i = math.max(1, n - 9), n do
      local ev = self.run.events[i]
      lines[#lines + 1] = string.format("%6.1f %s %s", ev.t, ev.kind, tostring(ev.room or ev.name or ev.text or ""))
    end
  end
  lines[#lines + 1] = "errors: " .. #self.errors.entries
  return lines
end

function App:setAutoOpen(on) self.store:settings().autoOpen = on and true or false end

function App:setScale(n)
  self.store:settings().hud.scale = n
  if self.hud then self.hud:setScale(n) end
end

function App:toggleHud()
  if not self.hud then return end
  self.hud:toggle()
  self.store:settings().hud.shown = self.hud.shown
end

function App:lockHud()
  local hud = self.store:settings().hud
  hud.locked = not hud.locked
  if self.hud then self.hud:setLocked(hud.locked) end
  return hud.locked
end

return App
```

- [ ] **Step 4: Run them to verify they pass**

Run: `.lua/bin/busted spec/app_spec.lua`
Expected: `13 successes`. If `hud.shown` assertions fail, check that the stub hud toggles `shown` before `toggleHud` reads it.

- [ ] **Step 5: Run the whole suite and commit**

Run: `.lua/bin/busted`
Expected: all green.

```bash
git add spec/app_spec.lua TankTrails/Core/App.lua
git commit -m "Add Core/App: run lifecycle, replay, view, actions"
```

---

### Task 13: UI/Theme, UI/Widgets, UI/TextBox, and a frame stub for tests

**Files:**
- Create: `spec/helpers/wow_stub.lua`, `TankTrails/UI/Theme.lua`, `TankTrails/UI/Widgets.lua`, `TankTrails/UI/TextBox.lua`
- Test: `spec/textbox_spec.lua`

**Interfaces:**
- Produces: `wow_stub.install()` / `.uninstall()` define global `CreateFrame`, `UIParent`, `ChatFontNormal`; every widget method exists, `SetText` stores `.text`, `Show`/`Hide` set `.shown`, `SetRotation` stores `.rotation`, `GetText` returns `.text`, `GetPoint` returns `"TOP", nil, "TOP", 0, 0`.
- Produces: `Theme.FONT`, `Theme.SIZE`, `Theme.COLORS`, `Theme.ARROW_TEXTURE`, `Theme.ARROW_ROTATION_SIGN`; `Widgets.paint(frame, bg, border)`, `Widgets.text(parent, size, color, justify)`, `Widgets.button(parent, label, onClick, width, height)`; `TextBox.create()` → `:show(title, text, onApply)`, `:hide()`, `.frame`, `.edit`, `.title`, `.apply`.

- [ ] **Step 1: Write the frame stub**

`spec/helpers/wow_stub.lua`:
```lua
local M = {}

local HANDLERS = {
  SetText = function(self, t) self.text = t end,
  GetText = function(self) return self.text or "" end,
  Show = function(self) self.shown = true end,
  Hide = function(self) self.shown = false end,
  IsShown = function(self) return self.shown ~= false end,
  SetRotation = function(self, r) self.rotation = r end,
  SetScale = function(self, s) self.scale = s end,
  GetScale = function(self) return self.scale or 1 end,
  GetWidth = function() return 100 end,
  GetHeight = function() return 100 end,
  GetPoint = function() return "TOP", nil, "TOP", 0, 0 end,
  SetScript = function(self, k, fn) self.scripts = self.scripts or {}; self.scripts[k] = fn end,
  GetScript = function(self, k) return self.scripts and self.scripts[k] end,
  SetTextColor = function(self, r, g, b, a) self.color = { r, g, b, a } end,
}

local function widget(kind)
  local w = { kind = kind, children = {}, shown = true }
  return setmetatable(w, { __index = function(_, k)
    if HANDLERS[k] then return HANDLERS[k] end
    if k == "CreateFontString" or k == "CreateTexture" then
      return function(self) local c = widget(k); table.insert(self.children, c); return c end
    end
    return function() end
  end })
end

function M.install()
  _G.CreateFrame = function(kind) return widget(kind) end
  _G.UIParent = widget("Frame")
  _G.ChatFontNormal = widget("Font")
end

function M.uninstall()
  _G.CreateFrame, _G.UIParent, _G.ChatFontNormal = nil, nil, nil
end

return M
```

- [ ] **Step 2: Write the failing TextBox test**

`spec/textbox_spec.lua`:
```lua
local stub = require("helpers.wow_stub")

describe("TextBox", function()
  local TextBox
  before_each(function()
    stub.install()
    package.loaded["UI.TextBox"] = nil
    TextBox = require("UI.TextBox")
  end)
  after_each(stub.uninstall)

  it("shows text read-only for export and with an apply button for import", function()
    local box = TextBox.create()
    assert.is_false(box.frame.shown)
    box:show("Export", "hello")
    assert.is_true(box.frame.shown)
    assert.are.equal("Export", box.title.text)
    assert.are.equal("hello", box.edit.text)
    assert.is_false(box.apply.shown)
    local got
    box:show("Import", "", function(text) got = text end)
    assert.is_true(box.apply.shown)
    box.edit.text = "pasted"
    box.apply.scripts.OnClick()
    assert.are.equal("pasted", got)
    box:hide()
    assert.is_false(box.frame.shown)
  end)
end)
```

- [ ] **Step 3: Run it to verify it fails**

Run: `.lua/bin/busted spec/textbox_spec.lua`
Expected: `module 'UI.TextBox' not found`.

- [ ] **Step 4: Write Theme, Widgets and TextBox**

`TankTrails/UI/Theme.lua`:
```lua
local _, ns = ...
ns = ns or {}

local Theme = {}
ns.Theme = Theme

Theme.FONT = "Fonts\\FRIZQT__.TTF"
Theme.SIZE = { title = 15, body = 12, small = 11 }

Theme.COLORS = {
  background = { 0.06, 0.07, 0.09, 0.85 }, border = { 1, 1, 1, 0.10 },
  text = { 0.90, 0.91, 0.93 }, muted = { 0.60, 0.64, 0.70 }, note = { 0.76, 0.82, 0.90 },
  dim = { 0.50, 0.54, 0.60 }, warning = { 1, 0.82, 0.30 }, accent = { 0.31, 0.82, 0.55 },
  chip = { 1, 1, 1, 0.06 }, chipBorder = { 1, 1, 1, 0.12 },
}

Theme.ARROW_TEXTURE = "Interface\\Minimap\\MinimapArrow"
-- SetRotation turns counter-clockwise for positive radians and Geometry.bearing is clockwise, so the HUD
-- applies -bearing. If the arrow turns the wrong way in game, set this to -1 (in-game checklist).
Theme.ARROW_ROTATION_SIGN = 1

return Theme
```

`TankTrails/UI/Widgets.lua`:
```lua
local _, ns = ...
ns = ns or {}
local Theme = ns.Theme or require("UI.Theme")

local Widgets = {}
ns.Widgets = Widgets

local BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function Widgets.paint(frame, bg, border)
  frame:SetBackdrop(BACKDROP)
  frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function Widgets.text(parent, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(Theme.FONT, size, "")
  fs:SetShadowOffset(1, -1)
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

function Widgets.button(parent, label, onClick, width, height)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width or 18, height or 18)
  Widgets.paint(b, Theme.COLORS.chip, Theme.COLORS.chipBorder)
  b.label = Widgets.text(b, Theme.SIZE.small, Theme.COLORS.text, "CENTER")
  b.label:SetPoint("CENTER")
  b.label:SetText(label)
  b:SetScript("OnClick", function() onClick() end)
  return b
end

return Widgets
```

`TankTrails/UI/TextBox.lua`:
```lua
local _, ns = ...
ns = ns or {}
local Theme = ns.Theme or require("UI.Theme")
local Widgets = ns.Widgets or require("UI.Widgets")

local TextBox = {}
TextBox.__index = TextBox
ns.TextBox = TextBox

-- One movable window with a multi-line edit box, used for export (copy) and import (paste, Apply).
function TextBox.create()
  local self = setmetatable({}, TextBox)
  local f = CreateFrame("Frame", "TankTrailsTextBox", UIParent, "BackdropTemplate")
  f:SetSize(540, 400)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  Widgets.paint(f, Theme.COLORS.background, Theme.COLORS.border)

  self.title = Widgets.text(f, Theme.SIZE.title, Theme.COLORS.text)
  self.title:SetPoint("TOPLEFT", 12, -10)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -36)
  scroll:SetPoint("BOTTOMRIGHT", -32, 44)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(480)
  edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
  scroll:SetScrollChild(edit)
  self.edit = edit

  self.close = Widgets.button(f, "Close", function() self:hide() end, 72, 22)
  self.close:SetPoint("BOTTOMRIGHT", -12, 12)
  self.apply = Widgets.button(f, "Import", function()
    if self.onApply then self.onApply(self.edit:GetText()) end
  end, 72, 22)
  self.apply:SetPoint("RIGHT", self.close, "LEFT", -8, 0)

  self.frame = f
  f:Hide()
  return self
end

function TextBox:show(title, text, onApply)
  self.title:SetText(title)
  self.edit:SetText(text or "")
  self.onApply = onApply
  if onApply then self.apply:Show() else self.apply:Hide() end
  self.frame:Show()
  self.edit:SetFocus()
  if text and text ~= "" then self.edit:HighlightText() end
end

function TextBox:hide() self.frame:Hide() end

return TextBox
```

- [ ] **Step 5: Run it to verify it passes**

Run: `.lua/bin/busted spec/textbox_spec.lua`
Expected: `1 success`.

- [ ] **Step 6: Commit**

```bash
git add spec/helpers/wow_stub.lua spec/textbox_spec.lua TankTrails/UI/Theme.lua TankTrails/UI/Widgets.lua TankTrails/UI/TextBox.lua
git commit -m "Add UI Theme, Widgets, TextBox and a frame stub for tests"
```

---

### Task 14: UI/Hud

**Files:**
- Create: `TankTrails/UI/Hud.lua`
- Test: `spec/hud_spec.lua`

**Interfaces:**
- Consumes: `Theme`, `Widgets`; the view table from Task 12.
- Produces: `Hud.create(settings, onClick)` → hud with `:update(view)`, `:toggle()`, `:setLocked(bool)`, `:setScale(n)`, fields `.frame`, `.line1..line4`, `.arrow`, `.shown`. `settings` is `TankTrailsDB.settings.hud` (`scale, locked, shown, point, x, y`).

- [ ] **Step 1: Write the failing test**

`spec/hud_spec.lua`:
```lua
local stub = require("helpers.wow_stub")

describe("Hud", function()
  local Hud, settings, clicks
  before_each(function()
    stub.install()
    package.loaded["UI.Hud"] = nil
    Hud = require("UI.Hud")
    settings = { scale = 1, locked = false, shown = true }
    clicks = 0
  end)
  after_each(stub.uninstall)

  local function hud() return Hud.create(settings, function() clicks = clicks + 1 end) end

  it("hides outside dungeons and shows learning mode", function()
    local h = hud()
    h:update({ mode = "none" })
    assert.is_false(h.frame.shown)
    h:update({ mode = "learning", dungeonName = "Cave", currentRoom = "Deep Cave", runSeconds = 65, counts = { rooms = 2, bosses = 1 } })
    assert.is_true(h.frame.shown)
    assert.are.equal("Cave  ·  learning  ·  1:05", h.line1.text)
    assert.are.equal("Deep Cave", h.line2.text)
    assert.are.equal("Learning: 2 rooms, 1 bosses", h.line3.text)
    assert.is_false(h.arrow.shown)
  end)

  it("shows route mode with arrow, notes, off-route and floor hints", function()
    local h = hud()
    h:update({ mode = "route", dungeonName = "The Deadmines", routeName = "Standard", currentRoom = "The Deadmines",
      runSeconds = 5, done = 1, total = 3, note = "first packs", next = "Mast Room", nextKind = "room", bearing = math.pi / 2 })
    assert.are.equal("The Deadmines  ·  Standard  ·  Bosses 1/3  ·  0:05", h.line1.text)
    assert.are.equal("The Deadmines", h.line2.text)
    assert.are.equal("Next: Mast Room", h.line3.text)
    assert.is_true(h.arrow.shown)
    assert.are.equal(-math.pi / 2, h.arrow.rotation)
    assert.are.equal("first packs", h.line4.text)
    h:update({ mode = "route", dungeonName = "D", routeName = "R", currentRoom = "Secret Cave", offRoute = "Secret Cave",
      runSeconds = 0, done = 0, total = 1, next = "Mr. Smite", nextKind = "boss", nextNote = "clear the deck", floorHint = "up", floorName = "Ironclad Cove" })
    assert.are.equal("? Secret Cave", h.line2.text)
    assert.are.equal("Next: Mr. Smite  (up to Ironclad Cove)", h.line3.text)
    assert.is_false(h.arrow.shown)
    assert.are.equal("next: clear the deck", h.line4.text)
    h:update({ mode = "route", dungeonName = "D", routeName = "R", runSeconds = 0, done = 1, total = 1, complete = true })
    assert.are.equal("Route complete", h.line3.text)
  end)

  it("toggles, scales, locks and clicks", function()
    local h = hud()
    h:toggle()
    assert.is_false(h.shown)
    assert.is_false(settings.shown)
    h:update({ mode = "learning", dungeonName = "C", runSeconds = 0, counts = { rooms = 0, bosses = 0 } })
    assert.is_false(h.frame.shown)
    h:toggle()
    assert.is_true(h.frame.shown)
    h:setScale(1.5)
    assert.are.equal(1.5, h.frame.scale)
    h:setLocked(true)
    h.frame.scripts.OnDragStart()
    assert.is_nil(h.frame.moving)
    h.frame.scripts.OnClick()
    assert.are.equal(1, clicks)
  end)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `.lua/bin/busted spec/hud_spec.lua`
Expected: `module 'UI.Hud' not found`.

- [ ] **Step 3: Write Hud**

`TankTrails/UI/Hud.lua`:
```lua
local _, ns = ...
ns = ns or {}
local Theme = ns.Theme or require("UI.Theme")
local Widgets = ns.Widgets or require("UI.Widgets")

local Hud = {}
Hud.__index = Hud
ns.Hud = Hud
Hud.WIDTH, Hud.HEIGHT = 300, 100

local function clock(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The four-line HUD of spec §7.1. A Button so a drag never counts as a click.
function Hud.create(settings, onClick)
  local self = setmetatable({ settings = settings, shown = settings.shown ~= false }, Hud)
  local f = CreateFrame("Button", "TankTrailsHud", UIParent, "BackdropTemplate")
  f:SetSize(Hud.WIDTH, Hud.HEIGHT)
  f:SetPoint(settings.point or "TOP", UIParent, settings.point or "TOP", settings.x or 0, settings.y or -140)
  f:SetScale(settings.scale or 1)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:RegisterForClicks("LeftButtonUp")
  Widgets.paint(f, Theme.COLORS.background, Theme.COLORS.border)
  f:SetScript("OnDragStart", function()
    if settings.locked then return end
    f.moving = true
    f:StartMoving()
  end)
  f:SetScript("OnDragStop", function()
    f.moving = nil
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint()
    settings.point, settings.x, settings.y = point, x, y
  end)
  f:SetScript("OnClick", function() onClick() end)

  self.line1 = Widgets.text(f, Theme.SIZE.small, Theme.COLORS.muted)
  self.line1:SetPoint("TOPLEFT", 10, -8)
  self.line1:SetPoint("TOPRIGHT", -10, -8)
  self.line2 = Widgets.text(f, Theme.SIZE.title, Theme.COLORS.text)
  self.line2:SetPoint("TOPLEFT", 10, -24)
  self.line2:SetPoint("TOPRIGHT", -10, -24)
  self.arrow = f:CreateTexture(nil, "OVERLAY")
  self.arrow:SetTexture(Theme.ARROW_TEXTURE)
  self.arrow:SetSize(18, 18)
  self.arrow:SetPoint("TOPLEFT", 10, -45)
  self.line3 = Widgets.text(f, Theme.SIZE.body, Theme.COLORS.accent)
  self.line3:SetPoint("TOPLEFT", 32, -47)
  self.line3:SetPoint("TOPRIGHT", -10, -47)
  self.line4 = Widgets.text(f, Theme.SIZE.body, Theme.COLORS.note)
  self.line4:SetPoint("TOPLEFT", 10, -66)
  self.line4:SetPoint("TOPRIGHT", -10, -66)
  self.line4:SetWordWrap(true)
  self.line4:SetMaxLines(2)

  self.frame = f
  if not self.shown then f:Hide() end
  return self
end

function Hud:update(view)
  local f = self.frame
  if view.mode == "none" or not self.shown then f:Hide(); return end
  f:Show()
  local c = Theme.COLORS
  if view.mode == "learning" then
    self.line1:SetText(string.format("%s  ·  learning  ·  %s", view.dungeonName, clock(view.runSeconds)))
    self.line2:SetText(view.currentRoom or "…")
    self.line3:SetText(string.format("Learning: %d rooms, %d bosses", view.counts.rooms, view.counts.bosses))
    self.arrow:Hide()
    self.line4:SetTextColor(c.dim[1], c.dim[2], c.dim[3], 1)
    self.line4:SetText("/tt promote when the run is done")
    return
  end
  self.line1:SetText(string.format("%s  ·  %s  ·  Bosses %d/%d  ·  %s", view.dungeonName, view.routeName,
    view.done or 0, view.total or 0, clock(view.runSeconds)))
  self.line2:SetText((view.offRoute and "? " or "") .. (view.currentRoom or "…"))
  if view.complete then
    self.line3:SetText("Route complete")
    self.arrow:Hide()
  else
    local hint = view.floorHint and string.format("  (%s to %s)", view.floorHint, view.floorName) or ""
    self.line3:SetText("Next: " .. tostring(view.next) .. hint)
    if view.bearing then
      self.arrow:Show()
      self.arrow:SetRotation(-view.bearing * Theme.ARROW_ROTATION_SIGN)
    else
      self.arrow:Hide()
    end
  end
  if view.note then
    self.line4:SetTextColor(c.note[1], c.note[2], c.note[3], 1)
    self.line4:SetText(view.note)
  elseif view.nextNote then
    self.line4:SetTextColor(c.dim[1], c.dim[2], c.dim[3], 1)
    self.line4:SetText("next: " .. view.nextNote)
  else
    self.line4:SetText("")
  end
end

function Hud:toggle()
  self.shown = not self.shown
  self.settings.shown = self.shown
  if self.shown then self.frame:Show() else self.frame:Hide() end
end

function Hud:setLocked(locked) self.settings.locked = locked end
function Hud:setScale(n) self.frame:SetScale(n) end

return Hud
```

- [ ] **Step 4: Run it to verify it passes**

Run: `.lua/bin/busted spec/hud_spec.lua`
Expected: `3 successes`.

- [ ] **Step 5: Commit**

```bash
git add spec/hud_spec.lua TankTrails/UI/Hud.lua
git commit -m "Add UI/Hud"
```

---

### Task 15: Core/Commands and Core/Boot

**Files:**
- Create: `TankTrails/Core/Commands.lua`, `TankTrails/Core/Boot.lua`
- Modify: `spec/helpers/fake_env.lua` (add `env.SlashCmdList = {}` next to `env.StaticPopupDialogs = {}`)
- Test: `spec/commands_spec.lua`

**Interfaces:**
- Consumes: App actions (Task 12), `TextBox` contract (Task 13), `Util.trim`.
- Produces: `Commands.parse(msg)` → `verb, rest`; `Commands.USAGE` (array of lines); `Commands.create(app, env, ui)` → commands with `:run(msg)` and `.handlers`; registers `/tt` when `env.SlashCmdList` exists. `ui.textBox()` returns the shared TextBox (created lazily).
- Boot wires the real game: `ADDON_LOADED` → defaults → `Store.new(TankTrailsDB, TankTrailsCharDB, TankTrails.shipped)` → `App.new{...}:start()` → `Commands.create`.

- [ ] **Step 1: Write the failing tests**

`spec/commands_spec.lua`:
```lua
local fake = require("helpers.fake_env")
local Commands = require("Core.Commands")

local function fakeApp(results)
  local app, calls = {}, {}
  for _, m in ipairs({ "toggleMap", "toggleHud", "lockHud", "note", "tickBoss", "promote", "switchRoute", "exportText",
                       "importText", "setAutoOpen", "setScale", "debugLines", "reset" }) do
    app[m] = function(_, ...)
      table.insert(calls, { m, ... })
      local r = results[m]
      if type(r) == "function" then return r(...) end
      if type(r) == "table" then return unpack(r) end
      return r
    end
  end
  app.errors = { entries = {} }
  function app:print(msg) table.insert(calls, { "print", msg }) end
  return app, calls
end

local function fakeUi()
  local box = { shown = {} }
  function box:show(title, text, onApply) table.insert(self.shown, { title = title, text = text }); self.onApply = onApply end
  function box:hide() self.hidden = true end
  return { textBox = function() return box end }, box
end

describe("Commands.parse", function()
  it("splits verb and rest, lower-casing the verb", function()
    local v, r = Commands.parse("  Note  pull the casters first ")
    assert.are.equal("note", v)
    assert.are.equal("pull the casters first", r)
    v, r = Commands.parse("")
    assert.are.equal("", v)
    assert.are.equal("", r)
  end)
end)

describe("Commands.create", function()
  it("registers /tt and dispatches simple verbs", function()
    local env = fake.new()
    local app, calls = fakeApp({ lockHud = true, note = { true, "saved" }, debugLines = { { "a", "b" } } })
    local cmd = Commands.create(app, env, fakeUi())
    assert.are.equal("/tt", env.SLASH_TANKTRAILS1)
    env.SlashCmdList.TANKTRAILS("hud")
    assert.are.same({ "toggleHud" }, calls[1])
    cmd:run("")
    assert.are.same({ "toggleMap" }, calls[2])
    cmd:run("lock")
    assert.are.same({ "print", "HUD locked." }, calls[4])
    cmd:run("note hello")
    assert.are.same({ "note", "hello" }, calls[5])
    assert.are.same({ "print", "saved" }, calls[6])
    cmd:run("boss")
    assert.are.same({ "tickBoss" }, calls[7])
    cmd:run("boss Cookie")
    assert.are.same({ "tickBoss", "Cookie" }, calls[8])
    cmd:run("route Fast")
    assert.are.same({ "switchRoute", "Fast" }, calls[9])
    cmd:run("debug")
    assert.are.same({ "print", "a" }, calls[11])
    cmd:run("autoopen off")
    assert.are.same({ "setAutoOpen", false }, calls[13])
    cmd:run("scale 1.2")
    assert.are.same({ "setScale", 1.2 }, calls[15])
    cmd:run("scale 9")
    assert.are.equal("print", calls[16][1])
    cmd:run("bogus")
    assert.truthy(calls[#calls][2]:find("/tt"))
  end)

  it("confirms before overwriting a route or wiping a dungeon", function()
    local env, st = fake.new()
    local app, calls = fakeApp({ promote = function(name, force) if force then return true, "done" end return "confirm" end,
                                 reset = function(force) if force then return true, "wiped" end return "confirm" end })
    local cmd = Commands.create(app, env, fakeUi())
    cmd:run("promote Mine")
    assert.are.equal("TANKTRAILS_CONFIRM", st.popup.which)
    st.popup.data.onYes()
    assert.are.same({ "promote", "Mine", true }, calls[2])
    assert.are.same({ "print", "done" }, calls[3])
    cmd:run("reset")
    st.popup.data.onYes()
    assert.are.same({ "reset", true }, calls[5])
  end)

  it("export opens the text box read-only; import applies after a confirm", function()
    local env, st = fake.new()
    local app, calls = fakeApp({ exportText = "TEXT",
      importText = function(text, force) if force then return true, "Imported X" end return "confirm", "X" end })
    local ui, box = fakeUi()
    local cmd = Commands.create(app, env, ui)
    cmd:run("export")
    assert.are.equal("TEXT", box.shown[1].text)
    assert.is_nil(box.onApply)
    cmd:run("import")
    assert.is_function(box.onApply)
    box.onApply("pasted")
    assert.truthy(st.popup.data)
    st.popup.data.onYes()
    assert.are.same({ "importText", "pasted", true }, calls[3])
    assert.is_true(box.hidden)
    assert.are.same({ "print", "Imported X" }, calls[4])
  end)

  it("errors lists the log or says none", function()
    local env = fake.new()
    local app, calls = fakeApp({})
    local cmd = Commands.create(app, env, fakeUi())
    cmd:run("errors")
    assert.are.same({ "print", "No errors." }, calls[1])
    app.errors.entries = { { label = "zone", message = "boom" } }
    cmd:run("errors")
    assert.are.same({ "print", "zone: boom" }, calls[2])
  end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted spec/commands_spec.lua`
Expected: `module 'Core.Commands' not found`.

- [ ] **Step 3: Write Commands and Boot**

`TankTrails/Core/Commands.lua`:
```lua
local _, ns = ...
ns = ns or {}
local Util = ns.Util or require("Core.Util")

local Commands = {}
Commands.__index = Commands
ns.Commands = Commands

Commands.USAGE = {
  "/tt - toggle the map",
  "/tt hud - toggle the HUD;  /tt lock - pin or unpin it;  /tt scale <0.5-2>",
  "/tt note <text> - note on the current step;  /tt boss [name] - tick a boss by hand",
  "/tt promote [name] - turn the run into a route;  /tt route <name> - switch route",
  "/tt export;  /tt import;  /tt autoopen on|off;  /tt debug;  /tt errors;  /tt reset",
}

function Commands.parse(msg)
  msg = Util.trim(msg)
  local verb, rest = msg:match("^(%S+)%s*(.*)$")
  return (verb or ""):lower(), Util.trim(rest or "")
end

function Commands.create(app, env, ui)
  local self = setmetatable({ app = app, env = env, ui = ui }, Commands)

  local function say(ok, msg)
    if msg then app:print(msg) end
    return ok
  end

  local function confirm(text, onYes)
    env.StaticPopupDialogs["TANKTRAILS_CONFIRM"] = env.StaticPopupDialogs["TANKTRAILS_CONFIRM"] or {
      text = "%s", button1 = "Yes", button2 = "No", timeout = 0, whileDead = true, hideOnEscape = true,
      preferredIndex = 3, OnAccept = function(_, data) data.onYes() end,
    }
    env.StaticPopup_Show("TANKTRAILS_CONFIRM", text, nil, { onYes = onYes })
  end

  local function usage()
    for _, line in ipairs(Commands.USAGE) do app:print(line) end
  end

  self.handlers = {
    [""] = function() app:toggleMap() end,
    hud = function() app:toggleHud() end,
    lock = function() app:print(app:lockHud() and "HUD locked." or "HUD unlocked.") end,
    note = function(rest) say(app:note(rest)) end,
    boss = function(rest) say(app:tickBoss(rest ~= "" and rest or nil)) end,
    promote = function(rest)
      local name = rest ~= "" and rest or nil
      local r, msg = app:promote(name)
      if r == "confirm" then
        confirm("A route with that name already exists. Replace it?", function() say(app:promote(name, true)) end)
      else
        say(r, msg)
      end
    end,
    route = function(rest) say(app:switchRoute(rest)) end,
    export = function()
      local text, msg = app:exportText()
      if text then ui.textBox():show("Export: copy this text (Ctrl+C)", text) else app:print(msg) end
    end,
    import = function()
      ui.textBox():show("Import: paste a dungeon file, then press Import", "", function(text)
        local r, msg = app:importText(text)
        if r == "confirm" then
          confirm("Replace saved data for " .. tostring(msg) .. "?", function()
            say(app:importText(text, true))
            ui.textBox():hide()
          end)
        else
          say(r, msg)
        end
      end)
    end,
    autoopen = function(rest)
      app:setAutoOpen(rest == "on")
      app:print(rest == "on" and "The map will open when you enter a dungeon." or "The map stays closed until /tt.")
    end,
    scale = function(rest)
      local n = tonumber(rest)
      if n and n >= 0.5 and n <= 2 then app:setScale(n) else app:print("Scale must be between 0.5 and 2.") end
    end,
    debug = function()
      for _, line in ipairs(app:debugLines()) do app:print(line) end
    end,
    errors = function()
      local entries = app.errors.entries
      if #entries == 0 then app:print("No errors.") return end
      for _, e in ipairs(entries) do app:print(e.label .. ": " .. e.message) end
    end,
    reset = function()
      local r, msg = app:reset()
      if r == "confirm" then
        confirm("Wipe the saved rooms, routes and notes for this dungeon?", function() say(app:reset(true)) end)
      else
        say(r, msg)
      end
    end,
    help = usage,
  }

  function self:run(msg)
    local verb, rest = Commands.parse(msg)
    local handler = self.handlers[verb]
    if handler then handler(rest) else usage() end
  end

  if env.SlashCmdList then
    env.SLASH_TANKTRAILS1 = "/tt"
    env.SlashCmdList.TANKTRAILS = function(msg) self:run(msg) end
  end
  return self
end

return Commands
```

`TankTrails/Core/Boot.lua` (game only, loaded last by the TOC):
```lua
local addonName, ns = ...

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, _, name)
  if name ~= addonName then return end
  self:UnregisterEvent("ADDON_LOADED")
  TankTrailsDB = ns.Init.applyDefaults(TankTrailsDB or {}, ns.Init.ACCOUNT_DEFAULTS)
  TankTrailsCharDB = ns.Init.applyDefaults(TankTrailsCharDB or {}, ns.Init.CHAR_DEFAULTS)
  local store = ns.Store.new(TankTrailsDB, TankTrailsCharDB, TankTrails.shipped)
  local textBox
  local ui = {
    hud = ns.Hud.create,
    textBox = function()
      textBox = textBox or ns.TextBox.create()
      return textBox
    end,
  }
  local app = ns.App.new({ env = _G, store = store, ui = ui })
  TankTrails.app = app
  app:start()
  TankTrails.commands = ns.Commands.create(app, _G, ui)
  app:print("Loaded. /tt help for commands.")
end)
```

- [ ] **Step 4: Run them to verify they pass**

Run: `.lua/bin/busted spec/commands_spec.lua`
Expected: `5 successes`.

- [ ] **Step 5: Commit**

```bash
git add spec/commands_spec.lua spec/helpers/fake_env.lua TankTrails/Core/Commands.lua TankTrails/Core/Boot.lua
git commit -m "Add Core/Commands (/tt) and Core/Boot"
```

---

### Task 16: Data include, TOC check, in-game checklist, install and verify

**Files:**
- Create: `TankTrails/Data/Dungeons.xml`, `docs/superpowers/notes/in-game-checklist.md`
- Test: `spec/toc_spec.lua`

**Interfaces:**
- Produces: a TOC whose every Lua file compiles; the checklist that gates the map plan (spec §9).

- [ ] **Step 1: Write the data include and the TOC test**

`TankTrails/Data/Dungeons.xml` (starter dungeons are added here by the starter-data plan, one `<Script file="Dungeons\Name.lua"/>` each):
```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/">
</Ui>
```

`spec/toc_spec.lua`:
```lua
describe("TankTrails.toc", function()
  it("lists only files that exist, and every Lua file compiles", function()
    local f = assert(io.open("TankTrails/TankTrails.toc"))
    local n = 0
    for line in f:lines() do
      local path = line:match("^([%w_\\%.]+%.[lx][um][al]?)%s*$")
      if path then
        path = "TankTrails/" .. path:gsub("\\", "/")
        local h = io.open(path)
        assert.is_not_nil(h, "missing " .. path)
        h:close()
        if path:match("%.lua$") then
          local chunk, err = loadfile(path)
          assert.is_not_nil(chunk, err)
          n = n + 1
        end
      end
    end
    assert.is_true(n >= 19)
  end)
end)
```

- [ ] **Step 2: Run the whole suite**

Run: `.lua/bin/busted`
Expected: all green, including the TOC check. If the TOC lists a file that does not exist yet, the test names it.

- [ ] **Step 3: Write the in-game checklist**

`docs/superpowers/notes/in-game-checklist.md`:
```markdown
# TankTrails in-game checklist (spec §9)

Install with `tools/install.sh "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"`, then `/reload`.
Note anything odd with `/tt debug` and `/tt errors`.

## API checks (run these first; they decide the map plan's branches)

Inside any dungeon, out of combat:

1. Native dungeon maps?
   `/dump C_Map.GetMapInfo(291)` — a table named The Deadmines means native map entries exist.
   Then: `/run local n=0 for id=1,3000 do local m=C_Map.GetMapInfo(id) if m and m.mapType==Enum.UIMapType.Dungeon then n=n+1 print(id, m.name) end end print(n.." dungeon maps")`
   Record the count. Zero means the map plan uses `art.kind = "tiles"` with ids from the listfile.
2. Target names out of combat?
   Target a mob without pulling: `/dump issecretvalue(UnitName("target"))` — `false` means pulls get target names.
3. Room keys: walk the Deadmines and `/dump GetMinimapZoneText()` in each area. Expect "The Deadmines", "Mast Room", "Goblin Foundry", "Ironclad Cove". Write down any that differ.
4. Boss events: kill Rhahk'Zor, then `/tt debug`. Expect a `boss` line with his name (or `#id` if the name was secret).
5. Art by file id (only if check 1 found zero): find one id in the community listfile (https://wago.tools/files, search `interface/worldmap/deadmines`), then `/run local t=UIParent:CreateTexture() t:SetPoint("CENTER") t:SetSize(256,256) print(t:SetTexture(<fileDataID>))`. A tile appears mid-screen and the call returns true. `/reload` clears it.

## Feature checks

### Setup
1. Log in. Chat shows "TankTrails: Loaded." `/tt help` lists the commands. No Lua errors; `/tt errors` says "No errors."
2. `/tt hud` hides and shows the HUD. Drag it; `/tt lock`; dragging no longer moves it. `/tt scale 1.3` grows it.

### Learning mode (a dungeon with no route)
1. Enter the dungeon. The HUD appears with the dungeon name, "learning", a clock, and the current room.
2. Walk into a new area. Line 2 changes within a second. `/tt debug` shows the room events.
3. Target a mob, pull it. After combat, `/tt debug` shows a pull line. Die on purpose if cheap; the pull's deaths count goes up (visible in the export later).
4. `/tt note pull these back` — chat confirms the note for the current room.
5. Kill the first boss. Line 3's boss count goes up.
6. `/reload` mid-run. The HUD comes back on the same room with the same counts.
7. Leave the dungeon. Chat says the run was recorded. `/tt promote` — chat confirms the route and step count.
8. `/tt export` opens a window with the dungeon text; it includes your note on that room's step. Copy it somewhere.

### Route mode
1. Re-enter the same dungeon. The HUD shows the route name, "Bosses 0/N", line 3 "Next: ..." and your note on line 4.
2. Walk the route. The next step advances on room changes and boss kills. Skip a room; the next boss kill re-anchors.
3. Walk somewhere not on the route. Line 2 shows "? <room>". Walk back; it clears.
4. `/tt note changed my mind` — line 4 updates at once. `/tt boss` ticks the next boss by hand (use it on a rare).
5. `/tt route <name>` with a wrong name lists the routes; with the right name switches.
6. `/tt import`, paste the exported text with one note edited, press Import, confirm. Line 4 shows the edited note.
7. `/tt reset`, confirm. The HUD drops back to learning mode. `/tt import` the saved text to restore.

### Arrow (needs two placed rooms; until the map plan lands, place by import)
1. In the exported text, give two consecutive route rooms positions, e.g. `floor = 1, x = 0.5, y = 0.8` and `floor = 1, x = 0.5, y = 0.2`, import it, stand in the first room. The arrow points up. If it points down, set `Theme.ARROW_ROTATION_SIGN = -1`.
```

- [ ] **Step 4: Install and run the checklist**

```bash
tools/install.sh "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"
```

Run the API checks and the feature checks in the beta. Record the results of API checks 1–5 at the top of the checklist file under a heading `## Results <date>` (the map plan reads them). Fix anything the feature checks turn up, with a busted test where the fix is in Model or Wow code.

- [ ] **Step 5: Commit**

```bash
git add TankTrails/Data/Dungeons.xml spec/toc_spec.lua docs/superpowers/notes/in-game-checklist.md
git commit -m "Add data include, TOC check and in-game checklist"
```

---

## Done when

- `.lua/bin/busted` is green.
- The feature checks in `docs/superpowers/notes/in-game-checklist.md` pass in the beta, and the API check results are recorded in that file.
- A recorded run promotes into a route that guides the next run, and an export round-trips through import.

Next plans: `2026-10-xx-tanktrails-map.md` (spec §7.2–7.4, gated by API check 1) and `2026-10-xx-tanktrails-starter-data.md` (spec §12).
