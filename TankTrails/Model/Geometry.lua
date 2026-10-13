local _, ns = ...
ns = ns or {}

local Geometry = {}
ns.Geometry = Geometry

-- Radians clockwise from screen-up, in image space where y grows downwards (spec §7.1).
function Geometry.bearing(a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  if dx == 0 and dy == 0 then return 0 end
  return math.atan2(dx, -dy)
end

function Geometry.grid(layerWidth, layerHeight, tileWidth, tileHeight)
  return math.ceil(layerWidth / tileWidth), math.ceil(layerHeight / tileHeight)
end

-- The largest rectangle with the image's aspect that fits the box, centered.
function Geometry.fit(imageW, imageH, boxW, boxH)
  local scale = math.min(boxW / imageW, boxH / imageH)
  local w, h = imageW * scale, imageH * scale
  return { x = (boxW - w) / 2, y = (boxH - h) / 2, w = w, h = h }
end

function Geometry.toImage(px, py, rect)
  local x, y = (px - rect.x) / rect.w, (py - rect.y) / rect.h
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return x, y
end

return Geometry
