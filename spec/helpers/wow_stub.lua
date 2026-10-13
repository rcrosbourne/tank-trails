local M = {}

local HANDLERS = {
  SetText = function(self, t) self.text = t end,
  GetText = function(self) return self.text or "" end,
  Show = function(self) self.shown = true end,
  Hide = function(self) self.shown = false end,
  IsShown = function(self) return self.shown ~= false end,
  SetRotation = function(self, r) self.rotation = r end,
  SetScale = function(self, s) self.scale = s end,
  GetScale = function(self) return self.scale or 1 end,
  GetWidth = function() return 100 end,
  GetHeight = function() return 100 end,
  GetPoint = function() return "TOP", nil, "TOP", 0, 0 end,
  SetScript = function(self, k, fn) self.scripts = self.scripts or {}; self.scripts[k] = fn end,
  GetScript = function(self, k) return self.scripts and self.scripts[k] end,
  SetTextColor = function(self, r, g, b, a) self.color = { r, g, b, a } end,
}

local function widget(kind)
  local w = { kind = kind, children = {}, shown = true, scripts = {} }
  return setmetatable(w, { __index = function(_, k)
    if HANDLERS[k] then return HANDLERS[k] end
    if k == "CreateFontString" or k == "CreateTexture" then
      return function(self) local c = widget(k); table.insert(self.children, c); return c end
    end
    return function() end
  end })
end

function M.install()
  _G.CreateFrame = function(kind) return widget(kind) end
  _G.UIParent = widget("Frame")
  _G.ChatFontNormal = widget("Font")
end

function M.uninstall()
  _G.CreateFrame, _G.UIParent, _G.ChatFontNormal = nil, nil, nil
end

return M
