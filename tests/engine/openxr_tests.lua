-- Pure Lua coverage for the OpenXR facade.  The native DLL is deliberately
-- absent in the ROM-free Linux tier: this proves desktop/headless fallback
-- and the quaternion math used to recenter headset poses.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local OpenXR = require("src.vr.OpenXR")

T.eq(OpenXR.configure({}), false, "VR stays opt-in without a flag")
T.eq(OpenXR.configure({ "--vr" }), true, "--vr requests the native path")
T.eq(OpenXR.init(), false, "non-Windows tests fall back without loading a DLL")
T.eq(OpenXR.isActive(), false, "failed/unavailable native path is never active")

local identity = { 0, 0, 0, 1 }
local product = OpenXR._qMul(identity, { 0.1, 0.2, 0.3, 0.9 })
T.check(math.abs(product[1] - 0.1) < 1e-9, "identity quaternion keeps x")
T.check(math.abs(product[4] - 0.9) < 1e-9, "identity quaternion keeps w")

local half = math.sqrt(0.5)
local turned = OpenXR._qRotate({ 0, half, 0, half }, { 0, 0, -1 })
T.check(math.abs(turned[1] + 1) < 1e-6, "90-degree yaw rotates forward to -X")
T.check(math.abs(turned[2]) < 1e-6, "yaw preserves vertical axis")
T.check(math.abs(turned[3]) < 1e-6, "90-degree yaw consumes forward Z")

-- Recentring chooses only a horizontal bearing. A user may press recenter
-- while looking down or with their head tilted; that pose must not redefine
-- gravity or rotate vertical movement into the ground plane.
local function axisQuat(x, y, z, angle)
  local s = math.sin(angle * 0.5)
  return { x * s, y * s, z * s, math.cos(angle * 0.5) }
end
local yawQ = axisQuat(0, 1, 0, math.rad(35))
local pitchQ = axisQuat(1, 0, 0, math.rad(25))
local rollQ = axisQuat(0, 0, 1, math.rad(-15))
local tiltedRecenter = OpenXR._qMul(yawQ,
  OpenXR._qMul(pitchQ, rollQ))
local levelOrigin = OpenXR._levelRecenterOrientation(tiltedRecenter)
local levelUp = OpenXR._qRotate(levelOrigin, { 0, 1, 0 })
T.check(math.abs(levelUp[1]) < 1e-6
        and math.abs(levelUp[2] - 1) < 1e-6
        and math.abs(levelUp[3]) < 1e-6,
        "recenter preserves gravity instead of inheriting head tilt")
local invLevel = { -levelOrigin[1], -levelOrigin[2],
                   -levelOrigin[3], levelOrigin[4] }
local verticalMove = OpenXR._qRotate(invLevel, { 0, 1, 0 })
T.check(math.abs(verticalMove[1]) < 1e-6
        and math.abs(verticalMove[2] - 1) < 1e-6
        and math.abs(verticalMove[3]) < 1e-6,
        "recenter keeps headset height purely vertical")

OpenXR.applyOptions({ vrCamera = "orbit", vrWorldScale = 80,
                      vrRenderDistance = 28, vrRefreshRate = 90,
                      vrTurnMode = "snap", vrSnapAngle = 45 })
T.eq(OpenXR._options.vrCamera, "orbit", "VR camera option reaches facade")
T.eq(OpenXR._options.vrWorldScale, 80, "VR world scale reaches facade")
T.eq(OpenXR._options.vrRenderDistance, 28,
     "Quest draw distance reaches the OpenXR view facade")
T.eq(OpenXR._options.vrRefreshRate, 90,
     "Quest refresh-rate target reaches the OpenXR facade")
OpenXR._requested = true
OpenXR._initialized = true
OpenXR._activityFocused = true
OpenXR._sessionFocused = true
T.check(OpenXR.ownsPacing(),
        "focused OpenXR session owns presentation pacing")
OpenXR._sessionFocused = false
T.check(not OpenXR.ownsPacing(),
        "MAX FPS limiter resumes while XR focus is absent")
-- Restore the --vr request used by the pointer tests below; only native
-- initialization/focus are meant to be absent after this pacing probe.
OpenXR._requested = true
OpenXR._initialized = false
OpenXR._activityFocused = true
OpenXR.applyOptions({ vrEnvironment = "ar" })
T.check(OpenXR.passthroughEnabled(), "AR environment enables passthrough")
OpenXR.applyOptions({ vrEnvironment = "vr" })
T.check(not OpenXR.passthroughEnabled(), "VR environment disables passthrough")
OpenXR._questBuild = false
OpenXR.applyOptions({ vrShadows = false })
T.check(OpenXR.shadowsEnabled(),
        "desktop keeps its existing shadow policy")
OpenXR._questBuild = true
T.check(not OpenXR.shadowsEnabled(),
        "Quest shadows default to off")
OpenXR.applyOptions({ vrShadows = true })
T.check(OpenXR.shadowsEnabled(),
        "Quest shadows can be explicitly enabled")
OpenXR._questBuild = false

-- First-person locomotion remaps stick-forward through the current headset
-- yaw while preserving A/B/START and the other non-direction buttons.
OpenXR.applyOptions({ vrCamera = "first_person" })
OpenXR._views = { { orientation = identity } }
T.eq(OpenXR._firstPersonMoveMask(0x11, { move_x = 0, move_y = 1 }), 0x11,
     "first-person forward is map north when looking north")
OpenXR._views = { { orientation = { 0, half, 0, half } } }
T.eq(OpenXR._firstPersonMoveMask(0x11, { move_x = 0, move_y = 1 }), 0x14,
     "first-person forward follows a physically turned headset")
T.eq(OpenXR._firstPersonMoveMask(0x12, { move_x = 0, move_y = 0 }), 0x10,
     "first-person stick deadzone releases movement but preserves A")
OpenXR._views = {}

OpenXR._frame = { recommendedWidth = 1832, recommendedHeight = 1920 }
local eyeW, eyeH = OpenXR.eyeDimensions()
T.eq(eyeW, 1832, "eye width follows the OpenXR runtime recommendation")
T.eq(eyeH, 1920, "eye height follows the OpenXR runtime recommendation")
OpenXR._frame = nil

local Pointer = require("src.vr.Pointer")
OpenXR._pointer = { active = true, x = 0.25, y = 0.5, down = true }
local hovered
local interactive = {
  onVRPointer = function(_, x, y) hovered = { x, y }; return true end,
}
Pointer.update({ stack = { top = function() return interactive end } })
T.check(Pointer.visible, "pointer is visible on an interactive menu")
T.check(math.abs(hovered[1] - 40) < 1e-6 and
        math.abs(hovered[2] - 72) < 1e-6,
        "normalized OpenXR hit maps to Game Boy UI pixels")
OpenXR._pointer = { active = false, x = 0.5, y = 0.5, down = false }
Pointer.update({ stack = { top = function() return interactive end } })
T.check(Pointer.visible,
        "cursor remains visible on a menu when the ray reaches its edge")

local dragged
local scrolling = {
  onVRPointer = function() return true end,
  vrScrollMetrics = function() return 0, 20, 4 end,
  vrSetScroll = function(_, value) dragged = value end,
}
OpenXR._pointer = { active = true, x = 0.96, y = 0.92, down = true }
Pointer.update({ stack = { top = function() return scrolling end } })
T.check(dragged and dragged >= 14,
        "dragging the persistent scrollbar reaches the bottom of a menu")
Pointer.update({ stack = { top = function() return {} end } })
T.check(not Pointer.visible, "pointer is invisible outside menus")

local Input = require("src.core.Input")
Input:init()
local hybridSelections = 0
local hybrid = {
  onVRPointer = function() hybridSelections = hybridSelections + 1; return true end,
}
Pointer.wasDown = false
Pointer.buttonNavigation = false
OpenXR._pointer = { active = true, x = 0.4, y = 0.5, down = false }
Input:applyVRState(0x02) -- down on the OpenXR left stick
Pointer.update({ input = Input,
  stack = { top = function() return hybrid end } })
Input:step()
T.check(Input:isDown("down") and Input:wasPressed("down"),
        "VR stick directions remain usable on pointer-enabled tablet menus")
T.eq(hybridSelections, 0,
     "stationary ray does not overwrite selection after stick navigation")
Input:applyVRState(0)
OpenXR._pointer = { active = true, x = 0.5, y = 0.5, down = false }
Pointer.update({ input = Input,
  stack = { top = function() return hybrid end } })
T.check(hybridSelections > 0,
        "deliberately moving the ray returns selection to pointer control")

Input:init()
local directClicks = 0
local clickable = {
  onVRPointer = function() return true end,
  onVRPointerClick = function() directClicks = directClicks + 1 end,
}
Pointer.wasDown = false
Input:applyVRState(0x10)
OpenXR._pointer = { active = true, x = 0.25, y = 0.25, down = true }
Pointer.update({ input = Input,
  stack = { top = function() return clickable end } })
Input:step()
T.eq(directClicks, 1, "one Quest trigger edge dispatches one laser click")
T.check(not Input:wasPressed("a"),
        "a dispatched laser click consumes the synthetic A edge")

Input:setVRMoveAxis(0.25, 0.75)
T.check(math.abs(Input.vrMoveAxis.x - 0.25) < 1e-9 and
        math.abs(Input.vrMoveAxis.y + 0.75) < 1e-9,
        "OpenXR analog movement is preserved in SDL stick coordinates")

local TouchControls = require("src.core.TouchControls")
T.check(not TouchControls._wantsOverlay(),
        "Quest/OpenXR never enables the phone touch overlay")


T.finish("openxr")
