-- Controller-ray menu pointer. The native bridge reports the intersection
-- with the physical OpenXR UI quad in normalized coordinates. A screen opts
-- in by implementing onVRPointer(x, y); therefore the dot cannot leak into
-- gameplay, battles, cutscenes or non-interactive dialogue.

local OpenXR = require("src.vr.OpenXR")
local VRScrollbar = require("src.ui.VRScrollbar")

local Pointer = {
  visible = false, x = 80, y = 72, down = false,
  buttonNavigation = false,
}

function Pointer.update(game)
  Pointer.visible = false
  Pointer.game = game
  if not (game and game.stack) then return end
  local top = game.stack:top()
  local hit = OpenXR.pointer()
  local pointable = top and top.onVRPointer and OpenXR.requested()
  if game.input and game.input.setVRNavigationEnabled then
    -- The laser and the thumbstick are complementary.  Disabling directions
    -- merely because a menu owns a ray made long tablet/options pages
    -- impossible to navigate without dragging the tiny scrollbar.
    game.input:setVRNavigationEnabled(true)
  end
  if not (pointable and hit) then
    Pointer.buttonNavigation = false
    Pointer.buttonAnchorX, Pointer.buttonAnchorY = nil, nil
    Pointer.wasDown = hit and hit.down or false
    return
  end
  if top.vrPointerEnabled and not top:vrPointerEnabled() then
    Pointer.wasDown = hit.down or false
    return
  end
  local x = math.max(0, math.min(159, hit.x * 160))
  local y = math.max(0, math.min(143, hit.y * 144))
  local directions = game.input and (tonumber(game.input.vrMask) or 0) % 0x10
                     or 0
  if directions ~= 0 and not Pointer.buttonNavigation then
    -- Once a direction is used, keep selection under button control while the
    -- hand naturally jitters.  A deliberate ray move or trigger press hands
    -- control back to the pointer.
    Pointer.buttonNavigation = true
    Pointer.buttonAnchorX, Pointer.buttonAnchorY = x, y
  end
  if Pointer.buttonNavigation and hit.active then
    local dx = x - (Pointer.buttonAnchorX or x)
    local dy = y - (Pointer.buttonAnchorY or y)
    if hit.down or dx * dx + dy * dy >= 36 then
      Pointer.buttonNavigation = false
      Pointer.buttonAnchorX, Pointer.buttonAnchorY = nil, nil
    end
  end
  local scroll, total, visible
  if top.vrScrollMetrics then
    scroll, total, visible = top:vrScrollMetrics()
  end
  local onScrollbar = hit.active and top.vrSetScroll
    and VRScrollbar.hit(x, y, total, visible)
  if hit.active and not onScrollbar and not Pointer.buttonNavigation
      and top:onVRPointer(x, y) ~= true then
    return
  end
  local clicked = hit.active and hit.down and not Pointer.wasDown
  Pointer.x, Pointer.y = x, y
  Pointer.down = hit.down and hit.active
  Pointer.visible = true
  if onScrollbar and hit.down then
    top:vrSetScroll(VRScrollbar.valueAt(y, scroll, total, visible))
    if game.input and game.input.consumeVRButton then
      game.input:consumeVRButton("a")
    end
  elseif clicked and top.onVRPointerClick then
    -- A pointer click is a UI action in its own right. Dispatch it directly
    -- instead of relying on the same physical trigger also surviving as a
    -- synthetic Game Boy A press until the next fixed update. This matters
    -- on the title menu, which can be opened and clicked between two steps.
    top:onVRPointerClick(x, y)
    if game.input and game.input.consumeVRButton then
      game.input:consumeVRButton("a")
    end
  end
  Pointer.wasDown = hit.down
end

function Pointer.draw()
  if not Pointer.visible then return end
  local top = Pointer.game and Pointer.game.stack and Pointer.game.stack:top()
  if not (top and top.onVRPointer) then return end
  if top.vrPointerEnabled and not top:vrPointerEnabled() then return end
  -- White laser with a dark hairline underneath so it stays visible over
  -- both white menu panels and coloured battle art.
  love.graphics.setLineWidth(4)
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.line(159, 143, Pointer.x, Pointer.y)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.line(159, 143, Pointer.x, Pointer.y)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.circle("fill", Pointer.x, Pointer.y, Pointer.down and 7 or 6)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("fill", Pointer.x, Pointer.y, Pointer.down and 5 or 4)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.circle("fill", Pointer.x, Pointer.y, 1.5)
  love.graphics.setLineWidth(1)
end

return Pointer
