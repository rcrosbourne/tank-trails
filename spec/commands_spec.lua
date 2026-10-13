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
