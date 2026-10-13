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
