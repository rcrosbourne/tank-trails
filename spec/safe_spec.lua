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
