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

  it("rejects malformed nested data with a message instead of raising", function()
    local d, err = Serialize.parse('TankTrails_RegisterDungeon({ id = 1, name = "x", routes = { 1 } })')
    assert.is_nil(d)
    assert.truthy(err:find("Import failed"))
    d, err = Serialize.parse('TankTrails_RegisterDungeon({ id = 1, name = "x", rooms = 5 })')
    assert.is_nil(d)
    assert.is_string(err)
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
