-- Persistent, browser-style scrollbar shared by every VR list menu.
-- It is drawn by the menu itself (never by the cursor), so it remains visible
-- even when the controller ray is outside the panel. The ray may click or
-- drag anywhere on the track to set an absolute scroll position.

local OpenXR = require("src.vr.OpenXR")

local Scrollbar = {
  x = 149,
  y = 5,
  width = 9,
  height = 134,
  minThumb = 16,
}

function Scrollbar.geometry(scroll, total, visible)
  total = math.max(0, tonumber(total) or 0)
  visible = math.max(1, tonumber(visible) or 1)
  local maximum = math.max(0, total - visible)
  local innerY = Scrollbar.y + 2
  local innerH = Scrollbar.height - 4
  local thumbH = maximum > 0
    and math.max(Scrollbar.minThumb, math.floor(innerH * visible / total))
    or innerH
  local travel = math.max(0, innerH - thumbH)
  local clamped = math.max(0, math.min(maximum, tonumber(scroll) or 0))
  local thumbY = innerY
  if maximum > 0 then
    thumbY = innerY + math.floor(travel * clamped / maximum + 0.5)
  end
  return thumbY, thumbH, maximum, travel, innerY
end

function Scrollbar.hit(x, y, total, visible)
  return OpenXR.requested()
     and (tonumber(total) or 0) > (tonumber(visible) or 0)
     and x >= Scrollbar.x - 2 and x <= Scrollbar.x + Scrollbar.width + 1
     and y >= Scrollbar.y and y <= Scrollbar.y + Scrollbar.height
end

function Scrollbar.valueAt(y, scroll, total, visible)
  local _, thumbH, maximum, travel, innerY =
    Scrollbar.geometry(scroll, total, visible)
  if maximum <= 0 or travel <= 0 then return 0 end
  local position = (y - innerY - thumbH / 2) / travel
  position = math.max(0, math.min(1, position))
  return math.floor(position * maximum + 0.5)
end

function Scrollbar.draw(scroll, total, visible)
  if not OpenXR.requested() or total <= visible then return end
  local thumbY, thumbH = Scrollbar.geometry(scroll, total, visible)
  love.graphics.push("all")
  love.graphics.setBlendMode("alpha")
  -- Pale trough + dark outline, with a wide rounded thumb like a modern
  -- browser scrollbar. It deliberately covers the extreme right edge.
  love.graphics.setColor(0.82, 0.82, 0.82, 0.96)
  love.graphics.rectangle("fill", Scrollbar.x, Scrollbar.y,
                          Scrollbar.width, Scrollbar.height, 3, 3)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", Scrollbar.x, Scrollbar.y,
                          Scrollbar.width, Scrollbar.height, 3, 3)
  love.graphics.setColor(0.18, 0.18, 0.18, 1)
  love.graphics.rectangle("fill", Scrollbar.x + 2, thumbY,
                          Scrollbar.width - 4, thumbH, 2, 2)
  love.graphics.pop()
end

return Scrollbar
