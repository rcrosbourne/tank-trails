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

  it("counts secret and nil payloads per field for the debug output", function()
    local ev, frame, _, st = harness()
    assert.are.same({}, ev:statsLines())
    st.secrets["Sneed"] = true
    frame:fire("BOSS_KILL", 4321, "Sneed")
    frame:fire("BOSS_KILL", 4322, "Sneed")
    frame:fire("ENCOUNTER_END", nil, "Rhahk'Zor", 1, 5, 1)
    assert.are.same({ "BOSS_KILL.name: 0 nil, 2 secret", "ENCOUNTER_END.id: 1 nil, 0 secret" }, ev:statsLines())
  end)
end)
