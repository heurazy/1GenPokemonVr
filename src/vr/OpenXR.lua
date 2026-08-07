-- Optional desktop/Quest OpenXR bridge.
--
-- The game and all headless tests keep working when the native DLL is
-- absent.  VR is only requested by --vr or GEN1RECOMP_VR=1, and the bridge
-- is initialized after LÖVE has created its OpenGL context.

local OpenXR = {
  _requested = false,
  _initialized = false,
  _active = false,
  _frame = nil,
  _views = {},
  _recenterPending = true,
  _cameraYaw = 0,
  _options = {},
  _snapReady = true,
  _pointer = { active = false, x = 0.5, y = 0.5, down = false },
  _controllers = {},
  _worldRenderer = nil,
  _worldRendererInvalidator = nil,
  _inWorldUI = false,
  _questBuild = false,
  _activityFocused = true,
  _sessionFocused = false,
  _initializing = false,
  _initAttempts = 0,
  _nextInitTime = 0,
  _refreshRate = 0,
  _refreshLogged = false,
}

local ffi
local C
local loadError
local bridgeDeclared = false

local function boolEnv(name)
  local value = os.getenv(name)
  return value == "1" or value == "true" or value == "TRUE"
end

local function platformName()
  if love and love.system and love.system.getOS then
    return love.system.getOS()
  end
  local ok, lib = pcall(require, "ffi")
  return ok and lib.os or "Unknown"
end

local function isSupportedPlatform()
  local osName = platformName()
  return osName == "Windows" or osName == "Android"
end

local function dllCandidates()
  local out = { "gen1openxr" }
  local explicit = os.getenv("GEN1RECOMP_OPENXR_DLL")
  if explicit and explicit ~= "" then table.insert(out, 1, explicit) end
  if not (love and love.filesystem) then return out end
  local roots = {}
  for _, getter in ipairs({ "getSource", "getSourceBaseDirectory",
                            "getWorkingDirectory" }) do
    if love.filesystem[getter] then
      local ok, value = pcall(love.filesystem[getter])
      if ok and type(value) == "string" and value ~= "" then
        roots[#roots + 1] = value
      end
    end
  end
  for _, base in ipairs(roots) do
    out[#out + 1] = base .. "/gen1openxr.dll"
    out[#out + 1] = base .. "/libgen1openxr.so"
    out[#out + 1] = base .. "/native/openxr_bridge/bin/gen1openxr.dll"
    out[#out + 1] = base .. "/native/openxr_bridge/build/Release/gen1openxr.dll"
  end
  return out
end

local function loadBridge()
  local ok
  ok, ffi = pcall(require, "ffi")
  if not ok then
    loadError = "LuaJIT FFI is unavailable"
    return false
  end
  if not bridgeDeclared then ffi.cdef[[
    typedef struct Gen1VRView {
      float position[3];
      float orientation[4];
      float fov[4];
    } Gen1VRView;

    typedef struct Gen1VRController {
      unsigned int active;
      float position[3];
      float orientation[4];
      unsigned int profile;
    } Gen1VRController;

    typedef struct Gen1VRFrame {
      unsigned int view_count;
      unsigned int recommended_width;
      unsigned int recommended_height;
      Gen1VRView views[2];
      Gen1VRController controllers[2];
    } Gen1VRFrame;

    typedef struct Gen1VRInput {
      unsigned int buttons;
      float move_x;
      float move_y;
      float turn_x;
      float turn_y;
      unsigned int pointer_active;
      float pointer_x;
      float pointer_y;
      unsigned int pointer_down;
      Gen1VRController controllers[2];
    } Gen1VRInput;

    int gen1openxr_init(void);
    int gen1openxr_begin_frame(Gen1VRFrame *frame);
    int gen1openxr_submit_frame(unsigned int framebuffer_width,
                                unsigned int framebuffer_height,
                                int projection_enabled);
    int gen1openxr_capture_ui(unsigned int source_width,
                              unsigned int source_height, int flip_y);
    int gen1openxr_capture_battle(unsigned int source_width,
                                  unsigned int source_height, int flip_y);
    int gen1openxr_capture_battle_enemy(unsigned int source_width,
                                        unsigned int source_height, int flip_y);
    int gen1openxr_capture_battle_attack(unsigned int source_width,
                                         unsigned int source_height, int flip_y);
    int gen1openxr_capture_battle_player(unsigned int source_width,
                                         unsigned int source_height, int flip_y);
    int gen1openxr_capture_battle_hud(unsigned int source_width,
                                      unsigned int source_height, int flip_y);
    int gen1openxr_poll_events(void);
    int gen1openxr_poll_input(Gen1VRInput *input);
    int gen1openxr_set_refresh_rate(float rate);
    float gen1openxr_get_refresh_rate(void);
    void gen1openxr_recenter_ui(void);
    void gen1openxr_cancel_frame(void);
    void gen1openxr_shutdown(void);
    const char *gen1openxr_last_error(void);
  ]]
    bridgeDeclared = true
  end
  local failures = {}
  for _, path in ipairs(dllCandidates()) do
    local loaded, lib = pcall(ffi.load, path)
    if loaded then
      C = lib
      return true
    end
    failures[#failures + 1] = path .. ": " .. tostring(lib)
  end
  loadError = "could not load gen1openxr.dll\n  " .. table.concat(failures, "\n  ")
  return false
end

local function qConjugate(q)
  return { -q[1], -q[2], -q[3], q[4] }
end

local function qMul(a, b)
  return {
    a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
    a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
    a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
    a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
  }
end

local function qRotate(q, v)
  local p = { v[1], v[2], v[3], 0 }
  local r = qMul(qMul(q, p), qConjugate(q))
  return { r[1], r[2], r[3] }
end

-- Recentring must only choose the user's horizontal bearing.  Using the
-- headset's full quaternion here makes whatever pitch/roll the user had at
-- that instant become the world's new "up", which tilts the floor and also
-- mixes forward motion into vertical height.  Keep gravity's +Y untouched
-- and extract only the yaw that points LOCAL -Z along the flattened headset
-- forward vector.  Looking straight up/down falls back to the right vector.
local function levelRecenterOrientation(q)
  local forward = qRotate(q, { 0, 0, -1 })
  local fx, fz = forward[1], forward[3]
  local flat = math.sqrt(fx * fx + fz * fz)
  local yaw
  if flat > 1e-6 then
    yaw = math.atan2(-fx, -fz)
  else
    local right = qRotate(q, { 1, 0, 0 })
    yaw = math.atan2(-right[3], right[1])
  end
  local half = yaw * 0.5
  return { 0, math.sin(half), 0, math.cos(half) }
end

local function sub(a, b)
  return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function bridgeError()
  if not C then return loadError end
  local p = C.gen1openxr_last_error()
  if p == nil then return "unknown OpenXR error" end
  return ffi.string(p)
end

function OpenXR.configure(args)
  OpenXR._requested = boolEnv("GEN1RECOMP_VR")
  if love and love.filesystem and love.filesystem.getInfo
      and love.filesystem.getInfo("quest_build.txt") then
    OpenXR._requested = true
    OpenXR._questBuild = true
  end
  for _, arg in ipairs(args or {}) do
    if arg == "--vr" then OpenXR._requested = true end
    if arg == "--no-vr" then OpenXR._requested = false end
  end
  return OpenXR._requested
end

function OpenXR.requested()
  return OpenXR._requested
end

function OpenXR.isQuestBuild()
  return OpenXR._questBuild
end

local function now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function scheduleRetry(message)
  OpenXR._initialized = false
  OpenXR._initializing = false
  OpenXR._initAttempts = OpenXR._initAttempts + 1
  -- Retry quickly during the Quest activity/runtime hand-off, then cap the
  -- delay so returning from sleep or a runtime restart can recover too.
  local delay = math.min(2, 0.25 * (2 ^ math.min(OpenXR._initAttempts - 1, 3)))
  OpenXR._nextInitTime = now() + delay
  loadError = message or loadError or "OpenXR initialization failed"
  print("OpenXR: " .. tostring(loadError)
        .. string.format(" (retry in %.2fs)", delay))
  return false
end

function OpenXR.init(force)
  if C and OpenXR._initialized then return true end
  if not OpenXR._requested or not isSupportedPlatform() then return false end
  if OpenXR._initializing then return false end
  if not force and now() < (OpenXR._nextInitTime or 0) then return false end
  OpenXR._initializing = true
  if not loadBridge() then
    return scheduleRetry(loadError)
  end
  local called, result = pcall(C.gen1openxr_init)
  if not called or result == 0 then
    local message = called and bridgeError() or tostring(result)
    -- A failed native initialization can already have created an instance or
    -- action set.  Tear it down before retrying; otherwise the old bridge
    -- returned success solely because the instance handle was non-null while
    -- the session itself was unusable.
    pcall(C.gen1openxr_shutdown)
    C = nil
    return scheduleRetry(message)
  end
  OpenXR._initialized = true
  OpenXR._initializing = false
  OpenXR._initAttempts = 0
  OpenXR._nextInitTime = 0
  OpenXR.setRefreshRate(OpenXR._options.vrRefreshRate or 90)
  return true
end

local function rawView(v)
  return {
    position = {
      tonumber(v.position[0]), tonumber(v.position[1]), tonumber(v.position[2]),
    },
    orientation = {
      tonumber(v.orientation[0]), tonumber(v.orientation[1]),
      tonumber(v.orientation[2]), tonumber(v.orientation[3]),
    },
    -- OpenXR order: angleLeft, angleRight, angleUp, angleDown.
    fov = {
      tonumber(v.fov[0]), tonumber(v.fov[1]),
      tonumber(v.fov[2]), tonumber(v.fov[3]),
    },
  }
end

local function recenter(views)
  local center = {
    (views[1].position[1] + views[2].position[1]) * 0.5,
    (views[1].position[2] + views[2].position[2]) * 0.5,
    (views[1].position[3] + views[2].position[3]) * 0.5,
  }
  OpenXR._originPosition = center
  OpenXR._originOrientation = levelRecenterOrientation(views[1].orientation)
  OpenXR._recenterPending = false
end

local function makeRelative(view)
  local inv = qConjugate(OpenXR._originOrientation)
  return {
    position = qRotate(inv, sub(view.position, OpenXR._originPosition)),
    orientation = qMul(inv, view.orientation),
    fov = view.fov,
    worldScale = tonumber(os.getenv("GEN1RECOMP_VR_SCALE"))
                 or OpenXR._options.vrWorldScale or 64,
    cameraMode = OpenXR._options.vrCamera or "immersive",
    cameraYaw = OpenXR._cameraYaw or 0,
    cameraDistance = tonumber(OpenXR._options.vrCameraDistance) or 100,
    cameraPitch = tonumber(OpenXR._options.vrCameraPitch) or 0,
    cameraHeight = tonumber(OpenXR._options.vrCameraHeight) or 0,
    cameraOffsetX = tonumber(OpenXR._options.vrCameraOffsetX) or 0,
    cameraOffsetZ = tonumber(OpenXR._options.vrCameraOffsetZ) or 0,
    headTracking = tonumber(OpenXR._options.vrHeadTracking) or 100,
    playerHeight = tonumber(OpenXR._options.vrPlayerHeight) or 130,
    renderScale = tonumber(OpenXR._options.vrRenderScale) or 75,
    renderDistance = tonumber(OpenXR._options.vrRenderDistance) or 28,
  }
end

-- Pokemon movement is cardinal, but in first person the cardinal direction
-- is selected from the world-space direction the player is actually looking.
-- This keeps "stick forward" intuitive after physically turning the head.
local function firstPersonMoveMask(mask, state)
  if OpenXR._options.vrCamera ~= "first_person" then return mask end
  local view = OpenXR._views[1]
  if not (view and view.orientation) then return mask end
  local mx, my = tonumber(state.move_x), tonumber(state.move_y)
  local directions = mask % 0x10
  local otherButtons = mask - directions
  if mx * mx + my * my < 0.1225 then return otherButtons end

  local forward = qRotate(view.orientation, { 0, 0, -1 })
  local right = qRotate(view.orientation, { 1, 0, 0 })
  local yaw = OpenXR._cameraYaw or 0
  local sy, cy = math.sin(yaw), math.cos(yaw)
  local function flatten(v)
    local x = v[1] * cy + v[3] * sy
    local z = -v[1] * sy + v[3] * cy
    local length = math.sqrt(x * x + z * z)
    if length < 0.001 then return nil end
    return x / length, z / length
  end
  local fx, fz = flatten(forward)
  local rx, rz = flatten(right)
  if not fx or not rx then return mask end
  local dx, dz = rx * mx + fx * my, rz * mx + fz * my
  if math.abs(dx) > math.abs(dz) then
    return otherButtons + (dx < 0 and 0x04 or 0x08)
  end
  return otherButtons + (dz < 0 and 0x01 or 0x02)
end

local PROFILE_NAMES = {
  [0] = "generic", [1] = "touch", [2] = "index",
  [3] = "vive", [4] = "wmr", [5] = "pico",
}

local function updateControllers(rawControllers)
  OpenXR._controllers = {}
  if not (rawControllers and OpenXR._originOrientation
          and OpenXR._originPosition) then return end
  local inv = qConjugate(OpenXR._originOrientation)
  for hand = 0, 1 do
    local raw = rawControllers[hand]
    if raw.active ~= 0 then
      local position = {
        tonumber(raw.position[0]), tonumber(raw.position[1]),
        tonumber(raw.position[2]),
      }
      local orientation = {
        tonumber(raw.orientation[0]), tonumber(raw.orientation[1]),
        tonumber(raw.orientation[2]), tonumber(raw.orientation[3]),
      }
      OpenXR._controllers[hand + 1] = {
        active = true,
        hand = hand == 0 and "left" or "right",
        position = qRotate(inv, sub(position, OpenXR._originPosition)),
        orientation = qMul(inv, orientation),
        profile = PROFILE_NAMES[tonumber(raw.profile)] or "generic",
      }
    end
  end
end

function OpenXR.setRefreshRate(rate)
  rate = tonumber(rate) or 90
  if not (C and OpenXR._initialized) then return false end
  local called, result = pcall(function()
    return C.gen1openxr_set_refresh_rate(rate)
  end)
  if not called then return false end
  if tonumber(result) == 0 then return false end
  local got, current = pcall(function()
    return C.gen1openxr_get_refresh_rate()
  end)
  if got then OpenXR._refreshRate = tonumber(current) or 0 end
  return true
end

function OpenXR.refreshRate()
  if C and OpenXR._initialized then
    local ok, current = pcall(function()
      return C.gen1openxr_get_refresh_rate()
    end)
    if ok and tonumber(current) and tonumber(current) > 0 then
      OpenXR._refreshRate = tonumber(current)
    end
  end
  return OpenXR._refreshRate or 0
end

function OpenXR.applyOptions(opts)
  opts = opts or {}
  OpenXR._options = opts
  if C and OpenXR._initialized then
    OpenXR.setRefreshRate(opts.vrRefreshRate or 90)
  end
end

-- Keep the environment choice available to both the native bridge and
-- headset-specific renderers.  The current desktop bridge remains opaque,
-- but callers must still be able to distinguish the requested AR mode from
-- the normal VR environment without reaching into the facade's internals.
function OpenXR.passthroughEnabled()
  return OpenXR._options.vrEnvironment == "ar"
end

-- Desktop keeps the renderer's existing shadow policy. Standalone Quest uses
-- an explicit opt-in because even the cheap character-decal fallback is drawn
-- once per eye and is unnecessary for the default performance profile.
function OpenXR.shadowsEnabled()
  if not OpenXR._questBuild then return true end
  return OpenXR._options.vrShadows == true
end

-- Pull semantic OpenXR actions into the engine input abstraction.  The
-- bridge supplies held states, so missing releases (runtime pause/controller
-- disconnect) naturally clear on the next successful poll.
function OpenXR.syncInput(input, dt)
  if OpenXR._questBuild and not OpenXR._activityFocused then
    -- Keep consuming lifecycle events while the Quest system menu owns the
    -- window. Do not sync actions or run game logic until the native OpenXR
    -- session itself confirms that immersive focus has returned. Quest Games
    -- Optimizer / Horizon ClearActivity can resume the Android activity while
    -- SDL misses love.focus(true), so relying only on that callback leaves the
    -- Lua game loop permanently suspended even though the app is visible.
    local lifecycle = 0
    if C then
      local called, result = pcall(C.gen1openxr_poll_events)
      if called then lifecycle = tonumber(result) or 0 end
    end
    if lifecycle >= 2 then
      OpenXR._activityFocused = true
      print("QuestVR focus recovered from native OpenXR session")
    else
      if input and input.applyVRState then input:applyVRState(0) end
      if input and input.setVRMoveAxis then input:setVRMoveAxis(0, 0) end
      OpenXR._pointer.active = false
      OpenXR._controllers = {}
      OpenXR._sessionFocused = false
      return false
    end
  end
  if not C then
    if input and input.applyVRState then input:applyVRState(0) end
    if input and input.setVRMoveAxis then input:setVRMoveAxis(0, 0) end
    return false
  end
  local state = ffi.new("Gen1VRInput[1]")
  local called, result = pcall(C.gen1openxr_poll_input, state)
  if not called or result == 0 then
    OpenXR._sessionFocused = false
    if input and input.applyVRState then input:applyVRState(0) end
    if input and input.setVRMoveAxis then input:setVRMoveAxis(0, 0) end
    OpenXR._pointer.active = false
    return false
  end
  OpenXR._sessionFocused = true
  if input and input.setVRMoveAxis then
    input:setVRMoveAxis(state[0].move_x, state[0].move_y)
  end
  local buttons = firstPersonMoveMask(tonumber(state[0].buttons), state[0])
  if input and input.applyVRState then input:applyVRState(buttons) end
  OpenXR._pointer = {
    active = state[0].pointer_active ~= 0,
    x = tonumber(state[0].pointer_x),
    y = tonumber(state[0].pointer_y),
    down = state[0].pointer_down ~= 0,
  }
  updateControllers(state[0].controllers)

  local x = tonumber(state[0].turn_x)
  local mode = OpenXR._options.vrTurnMode or "snap"
  if mode == "smooth" then
    local dead = math.abs(x) > 0.2 and x or 0
    OpenXR._cameraYaw = OpenXR._cameraYaw - dead * math.rad(90) * (dt or 0)
  elseif mode == "snap" then
    if math.abs(x) < 0.35 then OpenXR._snapReady = true end
    if OpenXR._snapReady and math.abs(x) > 0.7 then
      local degrees = tonumber(OpenXR._options.vrSnapAngle) or 30
      OpenXR._cameraYaw = OpenXR._cameraYaw - (x > 0 and 1 or -1)
                          * math.rad(degrees)
      OpenXR._snapReady = false
    end
  end
  -- The bridge reserves bit 8 for a controller-native recenter action.
  local recenterHeld = math.floor(tonumber(state[0].buttons) / 0x100) % 2 >= 1
  if recenterHeld and not OpenXR._recenterButtonHeld then OpenXR.recenter() end
  OpenXR._recenterButtonHeld = recenterHeld
  return true
end

function OpenXR.setActivityFocused(focused)
  local nextFocused = focused and true or false
  if OpenXR._activityFocused ~= nextFocused then
    print(nextFocused and "QuestVR activity focus resumed"
                      or "QuestVR activity focus suspended")
  end
  OpenXR._activityFocused = nextFocused
  if not OpenXR._activityFocused then
    OpenXR.cancelFrame()
    OpenXR._sessionFocused = false
    OpenXR._pointer.active = false
    OpenXR._controllers = {}
  end
end

function OpenXR.isFocused()
  if not OpenXR._questBuild then return true end
  return OpenXR._activityFocused and OpenXR._sessionFocused
end

-- xrWaitFrame is the presentation clock while an immersive session owns
-- focus. main.lua must not add the ordinary MAX FPS sleep on top of it.
function OpenXR.ownsPacing()
  return OpenXR._requested and OpenXR._initialized
    and OpenXR._activityFocused and OpenXR._sessionFocused
end

function OpenXR.pointer()
  return OpenXR._pointer
end

function OpenXR.controllers()
  return OpenXR._controllers
end

-- A headset-specific renderer may replace the engine's flat world composite
-- after every state has drawn.  This seam lives here rather than in a mod
-- loader so the renderer can stay agnostic about who owns the stereo pass.
function OpenXR.setWorldRenderer(renderer, invalidator)
  OpenXR._worldRenderer = type(renderer) == "function" and renderer or nil
  OpenXR._worldRendererInvalidator =
    type(invalidator) == "function" and invalidator or nil
end

-- Drop renderer-owned eye canvases/meshes before a large state transition.
-- The callback is optional so desktop, mod-free and older renderers remain
-- byte-for-byte on their existing path.
function OpenXR.invalidateWorldRenderer()
  local invalidate = OpenXR._worldRendererInvalidator
  if not invalidate then return true end
  local ok, err = pcall(invalidate)
  if not ok then print("OpenXR world renderer invalidate: " .. tostring(err)) end
  return ok
end

function OpenXR.hasWorldRenderer()
  return OpenXR._worldRenderer ~= nil
end

function OpenXR.renderWorld(renderer, zones, worldZones, deviceCanvas)
  local draw = OpenXR._worldRenderer
  if not (draw and OpenXR.isActive()) then return nil end
  local ok, canvas = pcall(draw, renderer, zones, worldZones, deviceCanvas)
  if not ok then
    print("OpenXR world renderer: " .. tostring(canvas))
    return nil
  end
  return canvas
end

-- True when menus and battle information were drawn as real world geometry
-- (for example on a tracked handheld device).  Renderer then omits the
-- fallback OpenXR quads, avoiding a flat panel over the stereoscopic scene.
function OpenXR.setInWorldUI(active)
  OpenXR._inWorldUI = active and true or false
end

function OpenXR.inWorldUI()
  return OpenXR._inWorldUI == true
end

function OpenXR.beginFrame()
  OpenXR._active = false
  OpenXR._frame = nil
  OpenXR._inWorldUI = false
  if not C and not OpenXR.init() then return false end
  local frame = ffi.new("Gen1VRFrame[1]")
  local result = C.gen1openxr_begin_frame(frame)
  if result <= 0 then
    OpenXR._sessionFocused = false
    return false
  end
  OpenXR._activityFocused = true
  OpenXR._sessionFocused = true
  if not OpenXR._refreshLogged then
    local hz = OpenXR.refreshRate()
    if hz > 0 then
      print(string.format("OpenXR display refresh: %.0f Hz", hz))
      OpenXR._refreshLogged = true
    end
  end
  if frame[0].view_count < 2 then
    C.gen1openxr_cancel_frame()
    return false
  end
  local raw = { rawView(frame[0].views[0]), rawView(frame[0].views[1]) }
  if OpenXR._recenterPending or not OpenXR._originOrientation then recenter(raw) end
  -- Use the poses predicted for this exact display frame; syncInput's copy
  -- is only the pre-frame fallback and would otherwise trail by one frame.
  updateControllers(frame[0].controllers)
  OpenXR._views = { makeRelative(raw[1]), makeRelative(raw[2]) }
  OpenXR._frame = {
    recommendedWidth = tonumber(frame[0].recommended_width),
    recommendedHeight = tonumber(frame[0].recommended_height),
  }
  OpenXR._active = true
  return true
end

function OpenXR.submitFrame(projectionEnabled)
  if not (C and OpenXR._active) then return false end
  local w, h = love.graphics.getPixelDimensions()
  local ok = C.gen1openxr_submit_frame(
    w, h, projectionEnabled == false and 0 or 1) ~= 0
  if not ok then
    OpenXR._sessionFocused = false
    print("OpenXR submit: " .. bridgeError())
  end
  OpenXR._active = false
  return ok
end

-- Copy the currently-bound LÖVE canvas into a native OpenXR quad layer.
-- Unlike drawing the same pixels into both projection images, a quad layer
-- has one physical pose and therefore converges correctly in both eyes.
function OpenXR.captureUI(width, height, fromCanvas)
  if not (C and OpenXR._active) then return false end
  local called, result = pcall(C.gen1openxr_capture_ui, width, height,
                               fromCanvas and 1 or 0)
  if not called then
    print("OpenXR UI: the native bridge is too old; rebuild gen1openxr.dll")
    return false
  end
  if result == 0 then print("OpenXR UI: " .. bridgeError()) end
  return result ~= 0
end

function OpenXR.captureBattle(width, height, fromCanvas)
  if not (C and OpenXR._active) then return false end
  local called, result = pcall(C.gen1openxr_capture_battle, width, height,
                               fromCanvas and 1 or 0)
  if not called then
    print("OpenXR battle layer: rebuild gen1openxr.dll")
    return false
  end
  if result == 0 then print("OpenXR battle layer: " .. bridgeError()) end
  return result ~= 0
end

local function captureBattleDepth(symbol, width, height, fromCanvas)
  if not (C and OpenXR._active) then return false end
  local called, result = pcall(C[symbol], width, height,
                               fromCanvas and 1 or 0)
  if not called then
    print("OpenXR battle depth layers: rebuild gen1openxr.dll")
    return false
  end
  if result == 0 then print("OpenXR battle layer: " .. bridgeError()) end
  return result ~= 0
end

function OpenXR.captureBattleEnemy(width, height, fromCanvas)
  return captureBattleDepth("gen1openxr_capture_battle_enemy", width, height, fromCanvas)
end

function OpenXR.captureBattleAttack(width, height, fromCanvas)
  return captureBattleDepth("gen1openxr_capture_battle_attack", width, height, fromCanvas)
end

function OpenXR.captureBattlePlayer(width, height, fromCanvas)
  return captureBattleDepth("gen1openxr_capture_battle_player", width, height, fromCanvas)
end

function OpenXR.captureBattleHUD(width, height, fromCanvas)
  return captureBattleDepth("gen1openxr_capture_battle_hud", width, height, fromCanvas)
end

function OpenXR.cancelFrame()
  if C and OpenXR._active then C.gen1openxr_cancel_frame() end
  OpenXR._active = false
end

function OpenXR.isActive()
  return OpenXR._active and OpenXR._views[2] ~= nil
end

function OpenXR.view(index)
  return OpenXR._views[index]
end

function OpenXR.eyeDimensions()
  -- Render the internal eye canvases at the runtime's recommended aspect.
  -- The Android mirror surface can have a different panel aspect; using half
  -- of that surface for the camera target stretches the recovered image even
  -- though submitFrame later scales it into the real OpenXR swapchains.
  local frame = OpenXR._frame
  local rw = frame and tonumber(frame.recommendedWidth) or nil
  local rh = frame and tonumber(frame.recommendedHeight) or nil
  if rw and rh and rw > 0 and rh > 0 then
    return math.max(1, math.floor(rw)), math.max(1, math.floor(rh))
  end
  local w, h = love.graphics.getPixelDimensions()
  return math.max(1, math.floor(w / 2)), math.max(1, h)
end

function OpenXR.recenter()
  OpenXR._recenterPending = true
  OpenXR._cameraYaw = 0
  if C then pcall(C.gen1openxr_recenter_ui) end
end

function OpenXR.lastError()
  return bridgeError()
end

function OpenXR.shutdown()
  if C then C.gen1openxr_shutdown() end
  C = nil
  OpenXR._initialized = false
  OpenXR._initializing = false
  OpenXR._nextInitTime = 0
  OpenXR._active = false
  OpenXR._inWorldUI = false
  OpenXR._sessionFocused = false
  OpenXR._refreshRate = 0
  OpenXR._refreshLogged = false
end

-- Exposed for ROM-free unit tests.
OpenXR._qMul = qMul
OpenXR._qRotate = qRotate
OpenXR._levelRecenterOrientation = levelRecenterOrientation
OpenXR._firstPersonMoveMask = firstPersonMoveMask

return OpenXR
