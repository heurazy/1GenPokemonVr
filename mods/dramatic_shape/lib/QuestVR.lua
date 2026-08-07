-- Quest standalone adapter for the engine-owned OpenXR bridge.
--
-- The upstream mod's VRXR module owns a Win32 OpenXR session through WGL.
-- The standalone Quest build already owns its Android OpenXR session in
-- src/vr/OpenXR.lua, so a second runtime must never be started here.  This
-- adapter only translates the bridge's predicted eye poses into the camera
-- records the official v1.5.4 stereo renderer already understands.

local V = ...

local Voxel = V.require("VoxelState")
local Voxel3D = V.require("Voxel3D")
local VoxelScene = V.require("VoxelScene")
local VoxelGrid = V.require("VoxelGrid")
local WorldCurve = V.require("WorldCurve")
local Water = V.require("Water")
local AntiAlias = V.require("AntiAlias")
local BattleCam = V.require("BattleCam")
local FirstPerson = V.require("FirstPerson")
local OverworldBattle = V.require("OverworldBattle")
local Pokedex = V.require("Pokedex")
local VRRig = V.require("VRRig")

local QuestVR = {
  paletteFor = nil,
  PROFILE_VERSION = 8,
  -- ADB telemetry on Quest 3 showed ample headroom once the stereo world was
  -- live. Keep enough resolution for a clean image; the real failure was the
  -- warm-up path evicting a completed eye, not an out-of-memory condition.
  DEFAULT_RENDER_SCALE = 0.75,
  MAX_EYE_PIXELS = 2 * 1024 * 1024,
}

local okOpenXR, OpenXR = pcall(require, "src.vr.OpenXR")
if not okOpenXR then OpenXR = nil end

local stereoCanvas = nil
local warned = {}
local QUEST_SPRITE_LEAN = math.rad(75)
local renderFailures = 0
local renderDisabled = false
local firstRender = true

-- The Quest path runs at headset refresh rather than the Game Boy's logic
-- rate. Keep the per-eye pose, FOV, camera matrices/vectors, eye descriptors
-- and returned canvas list alive between frames. Their contents still change
-- every view, but mutating stable tables avoids collecting the same graph
-- 72-120 times a second.
local framePoses = {
  { pos = { 0, 0, 0 }, quat = nil },
  { pos = { 0, 0, 0 }, quat = nil },
}
local frameFovs = { {}, {} }
local frameEyes = { {}, {} }
local frameCameras = { {}, {} }
local frameCameraScratch = { {}, {} }
local frameCanvases = {}
local framePivot = { 0, 0, 0 }
local frameAnchor = { 0, 0, 0 }
local frameLeftHandPose = {
  pos = { 0, 0, 0 },
  quat = { 0, 0, 0, 1 },
}
frameEyes.out = frameCanvases

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function wrapPi(angle)
  return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function questBuild()
  return OpenXR and OpenXR.isQuestBuild and OpenXR.isQuestBuild() or false
end

function QuestVR.supported()
  return questBuild()
end

function QuestVR.active()
  return questBuild() and OpenXR.isActive and OpenXR.isActive() or false
end

local function renderScale(optionPercent)
  -- The environment override remains useful for developer profiling. Normal
  -- Quest builds read the persisted VR menu percentage every frame so a
  -- quality change takes effect immediately without restarting the app.
  local env = tonumber(os.getenv("GEN1RECOMP_QUEST_VOXEL_SCALE"))
  local value = env or ((tonumber(optionPercent) or 75) / 100)
  return clamp(value, 0.5, 1.0)
end

local function writeDiagnostic(message)
  local line = os.date("!%Y-%m-%dT%H:%M:%SZ") .. " " .. tostring(message)
  pcall(function()
    if love.filesystem and love.filesystem.write then
      love.filesystem.write("quest-vr-last-error.log", line .. "\n")
    end
  end)
end

local function warnOnce(key, message)
  if warned[key] then return end
  warned[key] = true
  writeDiagnostic(message)
  local log = V.mod and V.mod.log
  if log and log.warn then
    pcall(log.warn, log, message)
  else
    print("DRAMATIC_SHAPE Quest: " .. tostring(message))
  end
end

local function failRender(key, message)
  if Voxel3D.abortScene then pcall(Voxel3D.abortScene, true) end
  Voxel3D.camera = nil
  VoxelScene.spriteLean = nil
  Pokedex.clear()
  if OpenXR and OpenXR.setInWorldUI then OpenXR.setInWorldUI(false) end
  renderFailures = renderFailures + 1
  warnOnce(key, message)
  -- A repeated failure is a capability failure, not a transient frame miss.
  -- Keep the game alive on this adapter's valid two-eye flat fallback rather
  -- than hammering the same GLES path until the process is terminated.
  if renderFailures >= 2 then
    renderDisabled = true
    warnOnce("disabled",
      "voxel stereo disabled after repeated GPU errors; using safe 2D VR fallback")
  end
end

local function renderDimensions(eyeW, eyeH, overrideScale)
  local scale2d = overrideScale or renderScale()
  local rw = math.max(1, math.floor(eyeW * scale2d + 0.5))
  local rh = math.max(1, math.floor(eyeH * scale2d + 0.5))
  local pixels = rw * rh
  if pixels > QuestVR.MAX_EYE_PIXELS then
    local shrink = math.sqrt(QuestVR.MAX_EYE_PIXELS / pixels)
    rw = math.max(1, math.floor(rw * shrink))
    rh = math.max(1, math.floor(rh * shrink))
  end
  return rw, rh
end

local function canvasFor(w, h)
  if stereoCanvas and stereoCanvas:getWidth() == w
      and stereoCanvas:getHeight() == h then
    return stereoCanvas
  end
  if stereoCanvas and stereoCanvas.release then
    pcall(stereoCanvas.release, stereoCanvas)
  end
  local ok, canvas = pcall(love.graphics.newCanvas, w, h, { dpiscale = 1 })
  if not (ok and canvas) then
    stereoCanvas = nil
    return nil
  end
  canvas:setFilter("linear", "linear")
  stereoCanvas = canvas
  return canvas
end

-- HEAD MOTION scales movement of the head centre, not the distance between
-- the eyes. Scaling each eye position independently shrinks the IPD at 50%
-- and collapses stereo entirely at 0%, which is both visually wrong and
-- uncomfortable. Preserve each eye's offset around the tracked centre while
-- applying the comfort control only to the centre's translation.
local function trackingPose(view, out, cx, cy, cz, tracking)
  out = out or { pos = {} }
  out.pos = out.pos or {}
  out.pos[1] = cx * tracking + view.position[1] - cx
  out.pos[2] = cy * tracking + view.position[2] - cy
  out.pos[3] = cz * tracking + view.position[3] - cz
  out.quat = view.orientation
  return out
end

local function trackingPoses(left, right, outLeft, outRight)
  local tracking = clamp((tonumber(left.headTracking)
                           or tonumber(right.headTracking) or 100) / 100,
                         0, 2)
  local cx = (left.position[1] + right.position[1]) * 0.5
  local cy = (left.position[2] + right.position[2]) * 0.5
  local cz = (left.position[3] + right.position[3]) * 0.5
  return trackingPose(left, outLeft, cx, cy, cz, tracking),
         trackingPose(right, outRight, cx, cy, cz, tracking)
end

local function fovFor(view, out)
  out = out or {}
  out.angleLeft = view.fov[1]
  out.angleRight = view.fov[2]
  out.angleUp = view.fov[3]
  out.angleDown = view.fov[4]
  return out
end

local function battleStage()
  local ok, arena, groundY = pcall(OverworldBattle.stage)
  if not ok then return nil end
  return arena, groundY
end

local function uiShowing()
  local ok, showing = pcall(function()
    local Game = require("src.core.Game")
    local top = Game.stack and Game.stack:top()
    return top ~= Game.overworld
           or (Game.overworld and Game.overworld.transitioning) or false
  end)
  return ok and showing or false
end

local function controllerPose(controller, out)
  if not (controller and controller.active and controller.position
          and controller.orientation) then return nil end
  out = out or { pos = {}, quat = {} }
  for i = 1, 3 do out.pos[i] = controller.position[i] end
  for i = 1, 4 do out.quat[i] = controller.orientation[i] end
  return out
end

local function firstPersonEyeHeight(heightCm, scale)
  return (tonumber(scale) or VRRig.FP_SCALE)
         * (clamp(tonumber(heightCm) or 130, 100, 200) / 100)
end

local function placement(ctx, view, pivot, anchor)
  local state, vw, vh = ctx.state, ctx.vw, ctx.vh
  local mode = view.cameraMode or "immersive"
  local worldScale = clamp((tonumber(view.worldScale) or 64) / 64, 0.5, 2)
  local distance = clamp((tonumber(view.cameraDistance) or 100) / 100,
                         0.5, 2)
  local yaw = tonumber(view.cameraYaw) or 0

  local arena, groundY = battleStage()
  if arena then
    local rec = BattleCam.rig(arena, groundY)
    local mount, mountYaw = VRRig.battleMount(rec.eye, rec.focus)
    pivot[1], pivot[2], pivot[3] = mount[1], mount[2], mount[3]
    anchor[1], anchor[2], anchor[3] = 0, 0, 0
    return pivot, anchor, VRRig.FP_SCALE * worldScale, mountYaw,
           false, true
  end

  if mode == "first_person" or Voxel.isFirstPerson() then
    local p = state.player
    if p then
      local gh = 0
      pcall(function()
        gh = VoxelScene.groundAt(state.map, p.cellX, p.cellY)
      end)
      anchor[1], anchor[2], anchor[3] = 0, 0, 0
      local scale = VRRig.FP_SCALE * worldScale
      -- Keep the selected virtual eye height in real metres even when WORLD
      -- SIZE changes. Converting metres through this frame's px/m scale keeps
      -- the floor at the requested height instead of shrinking or growing it.
      local eyeHeight = firstPersonEyeHeight(view.playerHeight, scale)
      return VRRig.fpPivot(p.px, p.py, gh, eyeHeight, pivot), anchor,
             scale, yaw, true, false
    end
  end

  local angle = Voxel.angle
  local pitch = tonumber(view.cameraPitch) or 0
  if mode == "overhead" then
    angle = 0
  elseif mode == "orbit" then
    angle = math.rad(pitch > 0 and pitch or 35)
  elseif pitch > 0 then
    angle = math.rad(pitch)
  end

  local ox = tonumber(view.cameraOffsetX) or 0
  local oz = tonumber(view.cameraOffsetZ) or 0
  VRRig.dioramaPivot(state.camera.x + vw / 2 + ox,
                     state.camera.y + vh / 2 + oz, pivot)
  local baseScale = VRRig.dioramaScale(vh, Voxel.FOCAL)
  local scale = baseScale * worldScale / distance
  local heightMetres = (tonumber(view.cameraHeight) or 0) / math.max(scale, 1)
  VRRig.dioramaAnchor(angle, heightMetres, anchor)
  return pivot, anchor, scale, yaw, false, false
end

-- Compose the two official eye canvases into the side-by-side framebuffer
-- consumed by the engine-owned Android bridge. Cleanup is deliberately
-- outside the protected draw: if a mobile driver rejects a draw or canvas
-- switch, the previous target and graphics stack are still restored.
local function composeEyes(target, canvases, eyeW, eyeH)
  local previous = love.graphics.getCanvas and love.graphics.getCanvas() or nil
  local pushed = false
  local ok, err = pcall(function()
    love.graphics.push("all")
    pushed = true
    love.graphics.setCanvas(target)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    for i = 1, 2 do
      local canvas = canvases[i]
      love.graphics.draw(canvas, (i - 1) * eyeW, 0, 0,
                         eyeW / canvas:getWidth(), eyeH / canvas:getHeight())
    end
  end)
  if love.graphics.setCanvas then pcall(love.graphics.setCanvas, previous) end
  if pushed and love.graphics.pop then pcall(love.graphics.pop) end
  return ok, err
end

-- While the asynchronous terrain mesh is warming, OpenXR still needs a
-- correctly shaped side-by-side projection image. Returning nil lets the
-- normal 2D framebuffer reach the native bridge, which then splits one flat
-- image down the middle and produces the broken view observed on the headset.
-- Duplicate the current flat world into both eyes until geometry is ready.
local function composeFallback(target, ctx, eyeW, eyeH)
  local renderer = ctx and ctx.renderer
  local source = renderer and renderer.worldActive and renderer.worldCanvas
                 or (ctx and ctx.deviceCanvas)
  if not source then return false, "no flat fallback canvas" end

  local previous = love.graphics.getCanvas and love.graphics.getCanvas() or nil
  local pushed = false
  local ok, err = pcall(function()
    love.graphics.push("all")
    pushed = true
    love.graphics.setCanvas(target)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)

    local sourceW, sourceH = source:getDimensions()
    local worldSource = renderer and source == renderer.worldCanvas
    -- A world canvas is much wider than one eye: cover the eye and crop its
    -- far edges. A 160x144 device fallback instead fits completely so menus
    -- and launch transitions remain readable.
    local scale
    if worldSource then
      scale = math.max(eyeW / sourceW, eyeH / sourceH)
    else
      scale = math.min(eyeW / sourceW, eyeH / sourceH)
    end
    local drawW, drawH = sourceW * scale, sourceH * scale
    local by = (eyeH - drawH) * 0.5
    for i = 1, 2 do
      local eyeX = (i - 1) * eyeW
      local bx = eyeX + (eyeW - drawW) * 0.5
      love.graphics.setScissor(eyeX, 0, eyeW, eyeH)
      love.graphics.draw(source, bx, by, 0, scale, scale)
    end
    love.graphics.setScissor()

    -- The world-only fallback still needs the normal anchored UI quad. When
    -- only the complete device canvas exists, it already contains the UI and
    -- submitting another quad would duplicate it.
    if OpenXR and OpenXR.setInWorldUI then
      OpenXR.setInWorldUI(not worldSource)
    end
  end)
  if love.graphics.setCanvas then pcall(love.graphics.setCanvas, previous) end
  if pushed and love.graphics.pop then pcall(love.graphics.pop) end
  return ok, err
end

local function fallbackStereo(ctx, eyeW, eyeH, target)
  target = target or canvasFor(eyeW * 2, eyeH)
  if not target then return nil end
  local ok, err = composeFallback(target, ctx, eyeW, eyeH)
  if not ok then warnOnce("fallback", "flat stereo fallback failed: " .. tostring(err)) end
  return ok and target or nil
end

function QuestVR.render(ctx)
  if not (QuestVR.active() and Voxel.active()) then
    Pokedex.clear()
    if OpenXR and OpenXR.setInWorldUI then OpenXR.setInWorldUI(false) end
    return nil
  end

  local sw, sh = love.graphics.getPixelDimensions()
  local eyeW = math.max(1, math.floor(sw / 2))
  local eyeH = math.max(1, sh)
  local target = canvasFor(eyeW * 2, eyeH)
  if not target then
    failRender("target", "could not allocate the stereo composition canvas")
    return nil
  end

  -- A disabled or unsupported voxel path still submits a valid stereo image;
  -- returning nil here is precisely what allows a mono framebuffer to be
  -- split into two unrelated halves by the native bridge.
  if renderDisabled or not Voxel3D.available() then
    Pokedex.clear()
    return fallbackStereo(ctx, eyeW, eyeH, target)
  end

  local left, right = OpenXR.view(1), OpenXR.view(2)
  if not (left and right and left.position and right.position
          and left.orientation and right.orientation
          and left.fov and right.fov) then
    Pokedex.clear()
    return fallbackStereo(ctx, eyeW, eyeH, target)
  end

  local recW, recH = eyeW, eyeH
  if OpenXR.eyeDimensions then
    local okDims, w, h = pcall(OpenXR.eyeDimensions)
    if okDims and tonumber(w) and tonumber(h) and w > 0 and h > 0 then
      recW, recH = w, h
    end
  end
  local rw, rh = renderDimensions(recW, recH, renderScale(left.renderScale))

  -- Clear dead Lua objects before the first pair of large GPU allocations.
  -- This happens once, behind the normal 2D fallback while terrain is still
  -- warming, and prevents a mesh upload plus a full GC from colliding later.
  if firstRender then
    firstRender = false
    pcall(collectgarbage, "collect")
  end

  local pivot, anchor, worldScale, yaw, firstPerson, battle =
    placement(ctx, left, framePivot, frameAnchor)
  local leftPose, rightPose = trackingPoses(left, right,
                                            framePoses[1], framePoses[2])

  -- Match the official PCVR first-person behaviour: the headset attitude is
  -- also the gameplay-facing attitude used by free movement and interaction.
  if firstPerson then
    local headYaw, headPitch = VRRig.headYawPitch(leftPose.quat)
    FirstPerson.yaw = wrapPi(headYaw + yaw)
    FirstPerson.pitch = clamp(headPitch,
                              FirstPerson.PITCH_UP,
                              FirstPerson.PITCH_DOWN)
  end

  -- The official v1.5.4 handheld Pokedex is real scene geometry. On Quest it
  -- rides the native bridge's tracked left controller and wears the engine's
  -- already-colorized 160x144 device canvas whenever a dialog/menu/battle is
  -- visible. Once lit, it replaces the fallback floating UI and battle quads.
  local controllers = OpenXR.controllers and OpenXR.controllers() or nil
  local hand = controllers and controllerPose(controllers[1], frameLeftHandPose)
  if hand and (firstPerson or battle) then
    Pokedex.place(hand, pivot, anchor, worldScale, yaw)
    if ctx.deviceCanvas and (battle or uiShowing()) then
      Pokedex.screen(ctx.deviceCanvas, 0, 0, 1, 1)
    end
  else
    Pokedex.clear()
  end
  local inWorldUI = Pokedex.frame and Pokedex.frame.tex ~= nil
  if OpenXR.setInWorldUI then OpenXR.setInWorldUI(inWorldUI) end

  for i = 1, 2 do
    local view = i == 1 and left or right
    local pose = i == 1 and leftPose or rightPose
    local eye = frameEyes[i]
    eye.camera = VRRig.eyeCamera(pose, fovFor(view, frameFovs[i]),
                                 pivot, anchor, worldScale, yaw,
                                 frameCameras[i], frameCameraScratch[i],
                                 clamp(tonumber(view.renderDistance)
                                       or VRRig.QUEST_FAR, 20, 36))
    eye.w = rw
    eye.h = rh
    eye.slot = i == 1 and "questL" or "questR"
    eye.adopt = firstPerson
  end
  frameEyes.cx, frameEyes.cy = pivot[1], pivot[3]

  -- A roaming headset has no single billboard pitch.  The official PCVR
  -- path uses the standing 75-degree pose, which remains readable from both
  -- eyes and avoids the cards disagreeing during head motion.
  local previousLean = VoxelScene.spriteLean
  VoxelScene.spriteLean = QUEST_SPRITE_LEAN
  local ok, canvases = pcall(VoxelScene.render, ctx.state, 0, 0,
                             ctx.vw, ctx.vh, QuestVR.paletteFor, frameEyes)
  VoxelScene.spriteLean = previousLean
  Voxel3D.camera = nil
  if not (ok and type(canvases) == "table"
          and canvases[1] and canvases[2]) then
    local status = frameEyes.status or "incomplete"
    if ok and status == "warming" then
      -- Expected while ChunkMesher finishes the destination map. Do not call
      -- abortScene, do not increment the failure counter, and never evict a
      -- completed eye. Submit a valid flat pair for these few frames.
      Pokedex.clear()
      return fallbackStereo(ctx, eyeW, eyeH, target)
    end
    if not ok then
      failRender("render", "stereo voxel render failed: " .. tostring(canvases))
    else
      failRender("render-" .. tostring(status),
        "stereo voxel renderer failed at " .. tostring(status))
    end
    return fallbackStereo(ctx, eyeW, eyeH, target)
  end

  local okCompose, composeErr = composeEyes(target, canvases, eyeW, eyeH)
  if not okCompose then
    failRender("compose", "stereo composition failed: " .. tostring(composeErr))
    return fallbackStereo(ctx, eyeW, eyeH, target)
  end
  renderFailures = 0
  return target
end

function QuestVR.invalidate()
  if stereoCanvas and stereoCanvas.release then
    pcall(stereoCanvas.release, stereoCanvas)
  end
  stereoCanvas = nil
  if Voxel3D.invalidate then pcall(Voxel3D.invalidate) end
  Voxel3D.camera = nil
  VoxelScene.spriteLean = nil
  Pokedex.clear()
  if OpenXR and OpenXR.setInWorldUI then OpenXR.setInWorldUI(false) end
  warned = {}
  renderFailures = 0
  renderDisabled = false
  firstRender = true
end

local function applyQuestDefaults(game)
  if not (questBuild() and game and game.save and game.save.options) then
    return
  end
  local opts = game.save.options
  opts.modOptions = opts.modOptions or {}
  local bucket = opts.modOptions[V.mod.id] or {}
  opts.modOptions[V.mod.id] = bucket
  if bucket.questProfileVersion == QuestVR.PROFILE_VERSION then return end

  local Pipelines = require("src.render.Pipelines")
  -- Standalone Quest now starts on the official 1ST rung: this is the same
  -- FirstPerson/FreeMove implementation as PCVR, not the engine's old flat
  -- immersive camera approximation. The VR options value is kept in sync so
  -- controller-relative movement uses the same facing immediately.
  Pipelines.setLevel("voxel", Voxel.FP_LEVEL)
  Pipelines.setLevel("tiltshift", 0)
  Pipelines.syncOptions(opts)
  opts.vrCamera = "first_person"
  if opts.vrPlayerHeight == nil then opts.vrPlayerHeight = 130 end
  if opts.vrRenderScale == nil then opts.vrRenderScale = 75 end
  if opts.vrRefreshRate == nil then opts.vrRefreshRate = 90 end
  -- Earlier Quest builds used an 18 m hard clip. Move existing profiles to a
  -- more comfortable default while keeping the new VR OPTION row adjustable.
  if tonumber(opts.vrRenderDistance) == nil
      or tonumber(opts.vrRenderDistance) <= 18 then
    opts.vrRenderDistance = 28
  end
  -- The dynamic shadow map is already unavailable on standalone Quest; also
  -- disable the remaining per-eye character decals in the default profile.
  opts.vrShadows = false
  if OpenXR and OpenXR.applyOptions then OpenXR.applyOptions(opts) end
  VoxelGrid.setting:setIndex(1, game)  -- no dense per-voxel wireframe in VR
  AntiAlias.setting:setIndex(1, game) -- stereo render scale replaces SSAA
  Water.setting:setIndex(2, game)     -- SKY reflection, no depth ray march
  WorldCurve.setting:setIndex(2, game)
  bucket.questProfileVersion = QuestVR.PROFILE_VERSION
  if game.writeOptions then pcall(game.writeOptions, game) end
end

function QuestVR.install()
  if questBuild() and OpenXR and OpenXR.setWorldRenderer then
    OpenXR.setWorldRenderer(function(renderer, zones, worldZones, deviceCanvas)
      local ok, canvas = pcall(function()
        local Game = require("src.core.Game")
        local state = Game and Game.overworld
        if not (state and state.map and state.camera) then return nil end
        local vw, vh = 320, 288
        if renderer and renderer.worldViewSize then
          vw, vh = renderer:worldViewSize()
        end
        return QuestVR.render({
          state = state,
          vw = vw,
          vh = vh,
          renderer = renderer,
          zones = zones,
          worldZones = worldZones,
          deviceCanvas = deviceCanvas,
        })
      end)
      if ok then return canvas end
      return failRender("adapter", "world renderer failed: " .. tostring(canvas))
    end, QuestVR.invalidate)
  end
  if questBuild() then BattleCam.still = true end
  if not V.mod or not V.mod.events then return end
  V.mod.events:on("game.ready", function(payload)
    applyQuestDefaults(payload and payload.game)
  end, 100)
end

-- Pure/contained seams used by the ROM-free mod SDK suite.
QuestVR._trackingPoses = trackingPoses
QuestVR._composeEyes = composeEyes
QuestVR._composeFallback = composeFallback
QuestVR._controllerPose = controllerPose
QuestVR._renderDimensions = renderDimensions
QuestVR._firstPersonEyeHeight = firstPersonEyeHeight

return QuestVR
