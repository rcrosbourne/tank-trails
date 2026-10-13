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
