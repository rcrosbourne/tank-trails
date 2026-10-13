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
