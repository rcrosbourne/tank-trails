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
