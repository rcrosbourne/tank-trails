local addonName, ns = ...

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, _, name)
  if name ~= addonName then return end
  self:UnregisterEvent("ADDON_LOADED")
  TankTrailsDB = ns.Init.applyDefaults(TankTrailsDB or {}, ns.Init.ACCOUNT_DEFAULTS)
  TankTrailsCharDB = ns.Init.applyDefaults(TankTrailsCharDB or {}, ns.Init.CHAR_DEFAULTS)
  local store = ns.Store.new(TankTrailsDB, TankTrailsCharDB, TankTrails.shipped)
  local textBox
  local ui = {
    hud = ns.Hud.create,
    textBox = function()
      textBox = textBox or ns.TextBox.create()
      return textBox
    end,
  }
  local app = ns.App.new({ env = _G, store = store, ui = ui })
  TankTrails.app = app
  TankTrails.commands = ns.Commands.create(app, _G, ui)
  app:start()
  app:print("Loaded. /tt help for commands.")
end)
