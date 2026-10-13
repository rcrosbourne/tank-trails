local _, ns = ...
ns = ns or {}
local Theme = ns.Theme or require("UI.Theme")
local Widgets = ns.Widgets or require("UI.Widgets")

local Hud = {}
Hud.__index = Hud
ns.Hud = Hud
Hud.WIDTH, Hud.HEIGHT = 300, 100

local function clock(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The four-line HUD of spec §7.1. A Button so a drag never counts as a click.
function Hud.create(settings, onClick)
  local self = setmetatable({ settings = settings, shown = settings.shown ~= false }, Hud)
  local f = CreateFrame("Button", "TankTrailsHud", UIParent, "BackdropTemplate")
  f:SetSize(Hud.WIDTH, Hud.HEIGHT)
  f:SetPoint(settings.point or "TOP", UIParent, settings.relativePoint or settings.point or "TOP", settings.x or 0, settings.y or -140)
  f:SetScale(settings.scale or 1)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:RegisterForClicks("LeftButtonUp")
  Widgets.paint(f, Theme.COLORS.background, Theme.COLORS.border)
  f:SetScript("OnDragStart", function()
    if settings.locked then return end
    f.moving = true
    f:StartMoving()
  end)
  f:SetScript("OnDragStop", function()
    f.moving = nil
    f:StopMovingOrSizing()
    local point, _, relativePoint, x, y = f:GetPoint()
    settings.point, settings.relativePoint, settings.x, settings.y = point, relativePoint, x, y
  end)
  f:SetScript("OnClick", function() onClick() end)

  self.line1 = Widgets.text(f, Theme.SIZE.small, Theme.COLORS.muted)
  self.line1:SetPoint("TOPLEFT", 10, -8)
  self.line1:SetPoint("TOPRIGHT", -10, -8)
  self.line2 = Widgets.text(f, Theme.SIZE.title, Theme.COLORS.text)
  self.line2:SetPoint("TOPLEFT", 10, -24)
  self.line2:SetPoint("TOPRIGHT", -10, -24)
  self.arrow = f:CreateTexture(nil, "OVERLAY")
  self.arrow:SetTexture(Theme.ARROW_TEXTURE)
  self.arrow:SetSize(18, 18)
  self.arrow:SetPoint("TOPLEFT", 10, -45)
  self.line3 = Widgets.text(f, Theme.SIZE.body, Theme.COLORS.accent)
  self.line3:SetPoint("TOPLEFT", 32, -47)
  self.line3:SetPoint("TOPRIGHT", -10, -47)
  self.line4 = Widgets.text(f, Theme.SIZE.body, Theme.COLORS.note)
  self.line4:SetPoint("TOPLEFT", 10, -66)
  self.line4:SetPoint("TOPRIGHT", -10, -66)
  self.line4:SetWordWrap(true)
  self.line4:SetMaxLines(2)

  self.frame = f
  if not self.shown then f:Hide() end
  return self
end

function Hud:update(view)
  local f = self.frame
  if view.mode == "none" or not self.shown then f:Hide(); return end
  f:Show()
  local c = Theme.COLORS
  if view.mode == "learning" then
    self.line1:SetText(string.format("%s  ·  learning  ·  %s", view.dungeonName, clock(view.runSeconds)))
    self.line2:SetText(view.currentRoom or "…")
    self.line3:SetText(string.format("Learning: %d rooms, %d bosses", view.counts.rooms, view.counts.bosses))
    self.arrow:Hide()
    self.line4:SetTextColor(c.dim[1], c.dim[2], c.dim[3], 1)
    self.line4:SetText("/tt promote when the run is done")
    return
  end
  self.line1:SetText(string.format("%s  ·  %s  ·  Bosses %d/%d  ·  %s", view.dungeonName, view.routeName,
    view.done or 0, view.total or 0, clock(view.runSeconds)))
  self.line2:SetText((view.offRoute and "? " or "") .. (view.currentRoom or "…"))
  if view.complete then
    self.line3:SetText("Route complete")
    self.arrow:Hide()
  else
    local hint = view.floorHint and string.format("  (%s to %s)", view.floorHint, view.floorName) or ""
    self.line3:SetText("Next: " .. tostring(view.next) .. hint)
    if view.bearing then
      self.arrow:Show()
      self.arrow:SetRotation(-view.bearing * Theme.ARROW_ROTATION_SIGN)
    else
      self.arrow:Hide()
    end
  end
  if view.note then
    self.line4:SetTextColor(c.note[1], c.note[2], c.note[3], 1)
    self.line4:SetText(view.note)
  elseif view.nextNote then
    self.line4:SetTextColor(c.dim[1], c.dim[2], c.dim[3], 1)
    self.line4:SetText("next: " .. view.nextNote)
  else
    self.line4:SetText("")
  end
end

function Hud:toggle()
  self.shown = not self.shown
  self.settings.shown = self.shown
  if self.shown then self.frame:Show() else self.frame:Hide() end
end

function Hud:setLocked(locked) self.settings.locked = locked end
function Hud:setScale(n) self.frame:SetScale(n) end

return Hud
