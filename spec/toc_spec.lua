describe("TankTrails.toc", function()
  it("lists only files that exist, and every Lua file compiles", function()
    local f = assert(io.open("TankTrails/TankTrails.toc"))
    local n = 0
    for line in f:lines() do
      local path = line:match("^([%w_\\%.]+%.[lx][um][al]?)%s*$")
      if path then
        path = "TankTrails/" .. path:gsub("\\", "/")
        local h = io.open(path)
        assert.is_not_nil(h, "missing " .. path)
        h:close()
        if path:match("%.lua$") then
          local chunk, err = loadfile(path)
          assert.is_not_nil(chunk, err)
          n = n + 1
        end
      end
    end
    assert.is_true(n >= 19)
  end)
end)
