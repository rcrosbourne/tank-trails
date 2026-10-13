local G = require("Model.Geometry")
local function near(a, b) return math.abs(a - b) < 1e-9 end

describe("Geometry", function()
  it("bearing is clockwise from up", function()
    local o = { x = 0.5, y = 0.5 }
    assert.is_true(near(0, G.bearing(o, { x = 0.5, y = 0.1 })))
    assert.is_true(near(math.pi / 2, G.bearing(o, { x = 0.9, y = 0.5 })))
    assert.is_true(near(math.pi, G.bearing(o, { x = 0.5, y = 0.9 })))
    assert.is_true(near(-math.pi / 2, G.bearing(o, { x = 0.1, y = 0.5 })))
    assert.is_true(near(math.pi / 4, G.bearing(o, { x = 0.6, y = 0.4 })))
    assert.are.equal(0, G.bearing(o, o))
  end)

  it("grid rounds up partial tiles", function()
    local cols, rows = G.grid(1002, 668, 256, 256)
    assert.are.equal(4, cols)
    assert.are.equal(3, rows)
  end)

  it("fit letterboxes wide and tall images", function()
    assert.are.same({ x = 0, y = 100, w = 800, h = 400 }, G.fit(1000, 500, 800, 600))
    assert.are.same({ x = 250, y = 0, w = 300, h = 600 }, G.fit(500, 1000, 800, 600))
  end)

  it("toImage maps canvas pixels into 0..1 and rejects outside", function()
    local rect = { x = 0, y = 100, w = 800, h = 400 }
    local x, y = G.toImage(400, 300, rect)
    assert.is_true(near(0.5, x) and near(0.5, y))
    assert.is_nil(G.toImage(400, 50, rect))
  end)
end)
