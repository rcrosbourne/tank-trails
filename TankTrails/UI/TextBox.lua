local _, ns = ...
ns = ns or {}
local Theme = ns.Theme or require("UI.Theme")
local Widgets = ns.Widgets or require("UI.Widgets")

local TextBox = {}
TextBox.__index = TextBox
ns.TextBox = TextBox

-- One movable window with a multi-line edit box, used for export (copy) and import (paste, Apply).
function TextBox.create()
  local self = setmetatable({}, TextBox)
  local f = CreateFrame("Frame", "TankTrailsTextBox", UIParent, "BackdropTemplate")
  f:SetSize(540, 400)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  Widgets.paint(f, Theme.COLORS.background, Theme.COLORS.border)

  self.title = Widgets.text(f, Theme.SIZE.title, Theme.COLORS.text)
  self.title:SetPoint("TOPLEFT", 12, -10)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -36)
  scroll:SetPoint("BOTTOMRIGHT", -32, 44)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(480)
  edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
  scroll:SetScrollChild(edit)
  self.edit = edit

  self.close = Widgets.button(f, "Close", function() self:hide() end, 72, 22)
  self.close:SetPoint("BOTTOMRIGHT", -12, 12)
  self.apply = Widgets.button(f, "Import", function()
    if self.onApply then self.onApply(self.edit:GetText()) end
  end, 72, 22)
  self.apply:SetPoint("RIGHT", self.close, "LEFT", -8, 0)

  self.frame = f
  f:Hide()
  return self
end

function TextBox:show(title, text, onApply)
  self.title:SetText(title)
  self.edit:SetText(text or "")
  self.onApply = onApply
  if onApply then self.apply:Show() else self.apply:Hide() end
  self.frame:Show()
  self.edit:SetFocus()
  if text and text ~= "" then self.edit:HighlightText() end
end

function TextBox:hide() self.frame:Hide() end

return TextBox
