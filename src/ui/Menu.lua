-- Generic bordered list menu with the blinking ▶ cursor.
-- items: { { label=..., onSelect=function }, ... }
-- Pops itself on B (unless cancelable=false); also on START only when
-- opts.startCloses is set -- pokered's wMenuWatchedKeys mask varies per
-- menu and only the start menu's adds PAD_START.

local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")
local VRScrollbar = require("src.ui.VRScrollbar")

local Menu = {}
Menu.__index = Menu

function Menu.new(game, items, opts)
  local self = setmetatable({}, Menu)
  opts = opts or {}
  self.game = game
  self.items = items
  self.index = 1
  self.tx = opts.tx or 10
  self.ty = opts.ty or 0
  self.tw = opts.tw or 10
  self.rowStep = opts.rowStep or 2
  -- maxVisible: cap the box to this many rows and scroll the rest instead
  -- of growing past it (e.g. the start menu, whose row count varies with
  -- save state and mod hooks); nil/unset keeps every caller's old
  -- behavior of sizing the box to fit all items.
  self.maxVisible = opts.maxVisible
  self.scroll = 0
  local visible = (self.maxVisible and math.min(self.maxVisible, #items))
    or #items
  self.th = opts.th or (visible * self.rowStep + 2)
  self.cancelable = opts.cancelable ~= false
  -- Whether START closes the menu.  In pokered a menu responds only to the
  -- keys in its wMenuWatchedKeys mask; the common PAD_A | PAD_B (and the
  -- list menu's PAD_A | PAD_B | PAD_SELECT) masks leave START unwatched, so
  -- only menus whose real mask includes PAD_START -- the start menu
  -- (engine/menus/draw_start_menu.asm) -- opt in here.
  self.startCloses = opts.startCloses or false
  self.onCancel = opts.onCancel
  -- BIT_NO_MENU_BUTTON_SOUND (wMiscFlags): the PC session runs its
  -- menus silent (home/window.asm HandleMenuInput_)
  self.noSound = opts.noSound or false
  self:clampScroll()
  return self
end

-- keeps self.index inside the visible [scroll+1, scroll+maxVisible] window;
-- callers that move self.index directly (e.g. restoring a saved cursor
-- position) should call this afterwards to scroll it into view
function Menu:clampScroll()
  if not (self.maxVisible and #self.items > self.maxVisible) then
    self.scroll = 0
    return
  end
  if self.index - self.scroll > self.maxVisible then
    self.scroll = self.index - self.maxVisible
  elseif self.index - self.scroll < 1 then
    self.scroll = self.index - 1
  end
end

function Menu:update(dt)
  local input = self.game.input
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #self.items
  elseif input:wasPressed("down") then
    self.index = self.index < #self.items and self.index + 1 or 1
  elseif input:wasPressed("a") then
    self:activateSelected()
  elseif self.cancelable and (input:wasPressed("b")
      or (self.startCloses and input:wasPressed("start"))) then
    -- HandleMenuInput_ returns for any watched key, but only replays
    -- SFX_PRESS_AB for the PAD_A | PAD_B branch -- so B beeps and START
    -- (when watched, e.g. the start menu) closes silently.
    if input:wasPressed("b") and not self.noSound then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  end
  self:clampScroll()
end

function Menu:activateSelected()
  -- HandleMenuInput_ (home/window.asm): SFX_PRESS_AB on every A press.
  if not self.noSound then
    require("src.core.Sound").play(self.game.data, "Press_AB")
  end
  local item = self.items[self.index]
  if not item then return end
  -- keepOpen entries run without closing the menu (e.g. the Pokédex CRY
  -- option keeps the side menu up).
  if not item.keepOpen then self.game.stack:pop() end
  if item.onSelect then item.onSelect() end
end

function Menu:onVRPointer(x, y)
  local left, right = self.tx * 8, (self.tx + self.tw) * 8
  if x < left or x > right then return true end
  local row = math.floor((y - (self.ty + 1) * 8) /
                         (self.rowStep * 8)) + 1
  local visible = (self.maxVisible and math.min(self.maxVisible, #self.items))
                  or #self.items
  if row >= 1 and row <= visible and self.items[self.scroll + row] then
    self.index = self.scroll + row
  end
  return true
end

function Menu:onVRPointerClick(x, y)
  self:onVRPointer(x, y)
  self:activateSelected()
  return true
end

function Menu:vrScroll(delta)
  local visible = (self.maxVisible and math.min(self.maxVisible, #self.items))
                  or #self.items
  local maxScroll = math.max(0, #self.items - visible)
  self.scroll = math.max(0, math.min(maxScroll, self.scroll + delta))
  self.index = math.max(self.scroll + 1,
                        math.min(self.scroll + visible, self.index))
end

function Menu:vrScrollInfo()
  local visible = (self.maxVisible and math.min(self.maxVisible, #self.items))
                  or #self.items
  return self.scroll > 0, self.scroll + visible < #self.items
end

function Menu:vrScrollState()
  local visible = (self.maxVisible and math.min(self.maxVisible, #self.items))
                  or #self.items
  return self.scroll, math.max(0, #self.items - visible)
end

function Menu:vrScrollMetrics()
  local visible = (self.maxVisible and math.min(self.maxVisible, #self.items))
                  or #self.items
  return self.scroll, #self.items, visible
end

function Menu:vrSetScroll(value)
  self:vrScroll((tonumber(value) or 0) - self.scroll)
end

function Menu:draw()
  Font.drawBox(self.tx, self.ty, self.tw, self.th)
  love.graphics.setColor(0, 0, 0, 1)
  local visible = (self.maxVisible and math.min(self.maxVisible, #self.items))
    or #self.items
  for row = 1, visible do
    local item = self.items[self.scroll + row]
    if not item then break end
    Font.draw(item.label, (self.tx + 2) * 8,
      (self.ty + row * self.rowStep - (self.rowStep - 1)) * 8)
  end
  local cursorRow = self.index - self.scroll
  Font.drawCode(Theme.cursor, (self.tx + 1) * 8,
    (self.ty + cursorRow * self.rowStep - (self.rowStep - 1)) * 8)
  -- moreArrow ($EE): the same "more below" glyph OptionRows/ManagerState
  -- use, sat on the bottom border like TextBox's page-advance cursor
  if self.maxVisible and self.scroll + self.maxVisible < #self.items then
    Font.drawCode(Theme.moreArrow, (self.tx + self.tw - 2) * 8,
      (self.ty + self.th - 2) * 8)
  end
  VRScrollbar.draw(self.scroll, #self.items, visible)
  love.graphics.setColor(1, 1, 1, 1)
end

return Menu
