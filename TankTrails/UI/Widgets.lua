local _, ns = ...
ns = ns or {}
local Theme = ns.Theme or require("UI.Theme")

local Widgets = {}
ns.Widgets = Widgets

local BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function Widgets.paint(frame, bg, border)
  frame:SetBackdrop(BACKDROP)
  frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function Widgets.text(parent, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(Theme.FONT, size, "")
  fs:SetShadowOffset(1, -1)
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

function Widgets.button(parent, label, onClick, width, height)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width or 18, height or 18)
  Widgets.paint(b, Theme.COLORS.chip, Theme.COLORS.chipBorder)
  b.label = Widgets.text(b, Theme.SIZE.small, Theme.COLORS.text, "CENTER")
  b.label:SetPoint("CENTER")
  b.label:SetText(label)
  b:SetScript("OnClick", function() onClick() end)
  return b
end

return Widgets
