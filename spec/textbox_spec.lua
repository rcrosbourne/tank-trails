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
