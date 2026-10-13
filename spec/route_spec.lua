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
