-- Dedicated OpenXR settings page, reached directly from the Pokemon START
-- menu. Settings persist in options.lua and are safe to edit outside VR.

local OpenXR = require("src.vr.OpenXR")
local OptionRows = require("src.ui.OptionRows")
local PaletteFX = require("src.render.PaletteFX")
local VRScrollbar = require("src.ui.VRScrollbar")

local VROptionsMenu = {}
VROptionsMenu.__index = VROptionsMenu
VROptionsMenu.isOpaque = true

VROptionsMenu.CAMERAS = {
  { "immersive", "IMMERSIVE" }, -- original/current OpenXR camera
  { "orbit", "ORBIT" },         -- elevated Animal Crossing-style follow
  { "overhead", "OVERHEAD" },   -- straight-down miniature view
  { "first_person", "FIRST PERSON" },
}
local SCALES = { 32, 40, 48, 56, 64, 72, 80, 96, 112, 128 }
local DISTANCES = { 70, 85, 100, 115, 130, 150 }
local PITCHES = { 0, 20, 30, 35, 45, 50, 55, 70 }
local HEIGHTS = { -32, -16, 0, 16, 32, 48, 64 }
local OFFSETS = { -64, -48, -32, -16, 0, 16, 32, 48, 64 }
local TRACKING = { 50, 75, 100, 125, 150 }
local TURNS = {
  { "snap", "SNAP" },
  { "smooth", "SMOOTH" },
  { "off", "OFF" },
}
local SNAP_ANGLES = { 15, 30, 45, 60 }
local PLAYER_HEIGHTS = { 100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200 }
local RENDER_SCALES = { 50, 60, 75, 85, 100 }
local RENDER_DISTANCES = { 20, 24, 28, 32, 36 }
local REFRESH_RATES = { 72, 80, 90, 120 }

local function indexOf(records, value, default)
  for i, record in ipairs(records) do
    local candidate = type(record) == "table" and record[1] or record
    if candidate == value then return i end
  end
  return default or 1
end

local function cycle(records, value, dir)
  local i = indexOf(records, value, 1)
  i = ((i - 1 + dir) % #records) + 1
  local record = records[i]
  return type(record) == "table" and record[1] or record
end

local function cameraLabel(value)
  return VROptionsMenu.CAMERAS[indexOf(VROptionsMenu.CAMERAS, value, 1)][2]
end

local function turnLabel(value)
  return TURNS[indexOf(TURNS, value, 1)][2]
end

local function desktopRowsFor(game)
  return {
    { id = "vrCamera", label = "CAMERA",
      value = function(g) return cameraLabel(g.save.options.vrCamera) end,
      step = function(g, dir)
        local o = g.save.options
        o.vrCamera = cycle(VROptionsMenu.CAMERAS, o.vrCamera, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrWorldScale", label = "WORLD SCALE",
      value = function(g) return tostring(g.save.options.vrWorldScale or 64) end,
      step = function(g, dir)
        local o = g.save.options
        o.vrWorldScale = cycle(SCALES, tonumber(o.vrWorldScale) or 64, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrCameraDistance", label = "VIEW DISTANCE",
      value = function(g)
        return tostring(g.save.options.vrCameraDistance or 100) .. "%"
      end,
      step = function(g, dir)
        local o = g.save.options
        o.vrCameraDistance = cycle(DISTANCES,
          tonumber(o.vrCameraDistance) or 100, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrCameraPitch", label = "VIEW PITCH",
      value = function(g)
        local pitch = tonumber(g.save.options.vrCameraPitch) or 0
        return pitch == 0 and "AUTO" or tostring(pitch) .. " DEG"
      end,
      step = function(g, dir)
        local o = g.save.options
        o.vrCameraPitch = cycle(PITCHES,
          tonumber(o.vrCameraPitch) or 0, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrCameraHeight", label = "VIEW HEIGHT",
      value = function(g) return tostring(g.save.options.vrCameraHeight or 0) end,
      step = function(g, dir)
        local o = g.save.options
        o.vrCameraHeight = cycle(HEIGHTS,
          tonumber(o.vrCameraHeight) or 0, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrCameraOffsetX", label = "VIEW OFFSET X",
      value = function(g) return tostring(g.save.options.vrCameraOffsetX or 0) end,
      step = function(g, dir)
        local o = g.save.options
        o.vrCameraOffsetX = cycle(OFFSETS,
          tonumber(o.vrCameraOffsetX) or 0, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrCameraOffsetZ", label = "VIEW OFFSET Z",
      value = function(g) return tostring(g.save.options.vrCameraOffsetZ or 0) end,
      step = function(g, dir)
        local o = g.save.options
        o.vrCameraOffsetZ = cycle(OFFSETS,
          tonumber(o.vrCameraOffsetZ) or 0, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrHeadTracking", label = "HEAD MOTION",
      value = function(g)
        return tostring(g.save.options.vrHeadTracking or 100) .. "%"
      end,
      step = function(g, dir)
        local o = g.save.options
        o.vrHeadTracking = cycle(TRACKING,
          tonumber(o.vrHeadTracking) or 100, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrTurnMode", label = "ORBIT TURN",
      value = function(g) return turnLabel(g.save.options.vrTurnMode) end,
      step = function(g, dir)
        local o = g.save.options
        o.vrTurnMode = cycle(TURNS, o.vrTurnMode, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrSnapAngle", label = "SNAP ANGLE",
      value = function(g) return tostring(g.save.options.vrSnapAngle or 30) end,
      step = function(g, dir)
        local o = g.save.options
        o.vrSnapAngle = cycle(SNAP_ANGLES,
                              tonumber(o.vrSnapAngle) or 30, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrRecenter", label = "RECENTER VIEW", value = function() return "PRESS A" end,
      activate = function() OpenXR.recenter() end },
    { id = "vrController", label = "VR CONTROLLER", value = function() return "OPENXR AUTO" end },
  }
end

local function worldSizeLabel(value)
  return tostring(math.floor((tonumber(value) or 64) * 100 / 64 + 0.5)) .. "%"
end

local function questRowsFor(game)
  return {
    -- Standalone Quest is now built around the official Dramatic Shape 1ST
    -- rig. Expose that fact instead of offering legacy camera modes which the
    -- Quest profile intentionally overrides on every launch.
    { id = "vrMode", label = "VR MODE",
      value = function() return "FIRST PERSON" end },
    { id = "vrWorldScale", label = "WORLD SIZE",
      value = function(g) return worldSizeLabel(g.save.options.vrWorldScale) end,
      step = function(g, dir)
        local o = g.save.options
        o.vrWorldScale = cycle(SCALES, tonumber(o.vrWorldScale) or 64, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrPlayerHeight", label = "PLAYER HEIGHT",
      value = function(g)
        return tostring(tonumber(g.save.options.vrPlayerHeight) or 130) .. " CM"
      end,
      step = function(g, dir)
        local o = g.save.options
        o.vrPlayerHeight = cycle(PLAYER_HEIGHTS,
          tonumber(o.vrPlayerHeight) or 130, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrRenderScale", label = "RENDER QUALITY",
      value = function(g)
        return tostring(tonumber(g.save.options.vrRenderScale) or 75) .. "%"
      end,
      step = function(g, dir)
        local o = g.save.options
        o.vrRenderScale = cycle(RENDER_SCALES,
          tonumber(o.vrRenderScale) or 75, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrRenderDistance", label = "DRAW DISTANCE",
      value = function(g)
        return tostring(tonumber(g.save.options.vrRenderDistance) or 28) .. " M"
      end,
      step = function(g, dir)
        local o = g.save.options
        o.vrRenderDistance = cycle(RENDER_DISTANCES,
          tonumber(o.vrRenderDistance) or 28, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrRefreshRate", label = "DISPLAY RATE",
      value = function(g)
        local requested = tonumber(g.save.options.vrRefreshRate) or 90
        local actual = OpenXR.refreshRate and OpenXR.refreshRate() or 0
        if actual > 0 and math.abs(actual - requested) >= 0.5 then
          return tostring(math.floor(actual + 0.5)) .. " HZ"
        end
        return tostring(requested) .. " HZ"
      end,
      step = function(g, dir)
        local o = g.save.options
        o.vrRefreshRate = cycle(REFRESH_RATES,
          tonumber(o.vrRefreshRate) or 90, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrShadows", label = "SHADOWS",
      value = function(g)
        return g.save.options.vrShadows == true and "ON" or "OFF"
      end,
      step = function(g)
        local o = g.save.options
        o.vrShadows = not (o.vrShadows == true)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrTurnMode", label = "TURN MODE",
      value = function(g) return turnLabel(g.save.options.vrTurnMode) end,
      step = function(g, dir)
        local o = g.save.options
        o.vrTurnMode = cycle(TURNS, o.vrTurnMode, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrSnapAngle", label = "SNAP ANGLE",
      value = function(g)
        if g.save.options.vrTurnMode ~= "snap" then return "--" end
        return tostring(g.save.options.vrSnapAngle or 30) .. " DEG"
      end,
      step = function(g, dir)
        local o = g.save.options
        if o.vrTurnMode ~= "snap" then return false end
        o.vrSnapAngle = cycle(SNAP_ANGLES,
                              tonumber(o.vrSnapAngle) or 30, dir)
        OpenXR.applyOptions(o)
        return true
      end },
    { id = "vrRecenter", label = "RECENTER VIEW",
      value = function() return "PRESS A" end,
      activate = function() OpenXR.recenter() end },
    { id = "vrFloorLevel", label = "FLOOR LEVEL",
      value = function() return "AUTO LEVEL" end },
    { id = "vrController", label = "CONTROLLERS",
      value = function() return "QUEST TOUCH" end },
    { id = "vrReset", label = "RESET VR SETUP",
      value = function() return "PRESS A" end,
      activate = function(g)
        local o = g.save.options
        o.vrCamera = "first_person"
        o.vrWorldScale = 64
        o.vrPlayerHeight = 130
        o.vrRenderScale = 75
        o.vrRenderDistance = 28
        o.vrRefreshRate = 90
        o.vrShadows = false
        o.vrTurnMode = "snap"
        o.vrSnapAngle = 30
        OpenXR.applyOptions(o)
        OpenXR.recenter()
        if g.writeOptions then g:writeOptions() end
      end },
  }
end

local function rowsFor(game)
  if OpenXR.isQuestBuild and OpenXR.isQuestBuild() then
    return questRowsFor(game)
  end
  return desktopRowsFor(game)
end

function VROptionsMenu.new(game)
  return setmetatable({ game = game, rows = rowsFor(game), index = 1,
                        scroll = 0 }, VROptionsMenu)
end

function VROptionsMenu:sgbPalettes(game)
  return PaletteFX.wholeNamed(game.data, "MEWMON")
end

function VROptionsMenu:update()
  local input, rows = self.game.input, self.rows
  local cancel = #rows + 1
  local changed = false
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or cancel
  elseif input:wasPressed("down") then
    self.index = self.index < cancel and self.index + 1 or 1
  elseif input:wasPressed("left") or input:wasPressed("right") then
    local row = rows[self.index]
    if row and row.step then
      changed = row.step(self.game, input:wasPressed("left") and -1 or 1)
    end
  elseif input:wasPressed("a") then
    local row = rows[self.index]
    if row and row.activate then
      row.activate(self.game)
    elseif row and row.step then
      changed = row.step(self.game, 1)
    elseif self.index == cancel then
      self.game.stack:pop()
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self.game.stack:pop()
  end
  if changed and self.game.writeOptions then self.game:writeOptions() end
  self.scroll = OptionRows.clampScroll(self.index, self.scroll, #rows, cancel)
end

function VROptionsMenu:onVRPointer(_, y)
  if y >= 128 then
    self.index = #self.rows + 1
  else
    local slot = math.floor(y / 32) + 1
    local index = self.scroll + slot
    if slot >= 1 and slot <= OptionRows.VISIBLE and self.rows[index] then
      self.index = index
    end
  end
  return true
end

function VROptionsMenu:vrScroll(delta)
  local maxScroll = math.max(0, #self.rows - OptionRows.VISIBLE)
  self.scroll = math.max(0, math.min(maxScroll, self.scroll + delta))
  if self.index <= #self.rows then
    self.index = math.max(self.scroll + 1,
      math.min(self.scroll + OptionRows.VISIBLE, self.index))
  end
end

function VROptionsMenu:vrScrollInfo()
  return self.scroll > 0, self.scroll + OptionRows.VISIBLE < #self.rows
end

function VROptionsMenu:vrScrollState()
  return self.scroll, math.max(0, #self.rows - OptionRows.VISIBLE)
end

function VROptionsMenu:vrScrollMetrics()
  return self.scroll, #self.rows, OptionRows.VISIBLE
end

function VROptionsMenu:vrSetScroll(value)
  self:vrScroll((tonumber(value) or 0) - self.scroll)
end

function VROptionsMenu:draw()
  OptionRows.draw(self.game, self.rows, self.index, self.scroll,
                  "CANCEL", #self.rows + 1)
  VRScrollbar.draw(self.scroll, #self.rows, OptionRows.VISIBLE)
end

return VROptionsMenu
