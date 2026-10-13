local _, ns = ...
ns = ns or {}

local Theme = {}
ns.Theme = Theme

Theme.FONT = "Fonts\\FRIZQT__.TTF"
Theme.SIZE = { title = 15, body = 12, small = 11 }

Theme.COLORS = {
  background = { 0.06, 0.07, 0.09, 0.85 }, border = { 1, 1, 1, 0.10 },
  text = { 0.90, 0.91, 0.93 }, muted = { 0.60, 0.64, 0.70 }, note = { 0.76, 0.82, 0.90 },
  dim = { 0.50, 0.54, 0.60 }, warning = { 1, 0.82, 0.30 }, accent = { 0.31, 0.82, 0.55 },
  chip = { 1, 1, 1, 0.06 }, chipBorder = { 1, 1, 1, 0.12 },
}

Theme.ARROW_TEXTURE = "Interface\\Minimap\\MinimapArrow"
-- SetRotation turns counter-clockwise for positive radians and Geometry.bearing is clockwise, so the HUD
-- applies -bearing. If the arrow turns the wrong way in game, set this to -1 (in-game checklist).
Theme.ARROW_ROTATION_SIGN = 1

return Theme
