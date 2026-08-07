-- Native LÖVE2D port of Pokemon Red. A packaged build creates its private
-- game-data cache from a user-provided ROM on first boot.
--
-- Set POKEPORT_EDITOR=1 or pass `--editor` to `love .` to boot the save
-- editor tool (tools/save-editor/) instead of the game.

local editorMode = os.getenv("POKEPORT_EDITOR") == "1" or POKEPORT_EDITOR_MODE == true
local OpenXR = require("src.vr.OpenXR")

local Game, EditorApp, Importer

local autopilot -- optional scripted-input dev tool (tests/autopilot.lua)
local driverCo  -- optional frame-driver (POKEPORT_DRIVER=file.lua): a
                -- coroutine that receives `Game` and yields once per
                -- frame; used headless (xvfb) for scripted screenshots
local importerPointerDown = false

-- LÖVE's stdout is not reliably forwarded to logcat by the Android shell.
-- Mirror launcher/boot diagnostics to Android's native logger so a Quest
-- that goes black while leaving the process alive can still be diagnosed.
local function bootLog(message, priority)
  message = tostring(message)
  print("QuestBoot: " .. message)
  if love.system.getOS() ~= "Android" then return end
  pcall(function()
    local ffi = require("ffi")
    ffi.cdef[[int __android_log_write(int prio, const char *tag, const char *text);]]
    local log = ffi.load("log")
    log.__android_log_write(priority or 4, "Gen1PokemonVR", message)
  end)
end

-- --speed N / POKEPORT_SPEED=N: run the logic clock N times faster without
-- touching audio (src/core/GameSpeed.lua).  Overrides the saved option so a
-- bot or screenshot run is not at the mercy of the player's last choice.
local speedOverride = tonumber(os.getenv("POKEPORT_SPEED"))

-- POKEPORT_TOUCH=1 forces the mobile on-screen controls on and lets the
-- mouse stand in for a finger, so the overlay can be exercised on desktop
-- (see src/core/TouchControls.lua).
local mouseTouch = os.getenv("POKEPORT_TOUCH") == "1"

-- How many times to run a scripted act+step loop per rendered frame.  Only
-- scripted runs use this; interactive play fast-forwards through
-- Game.speedOverride / the GAME SPEED option instead.
local function scriptedIterations()
  if not (autopilot or driverCo) then return 1 end
  return math.max(1, math.floor(require("src.core.GameSpeed").clamp(speedOverride)))
end

local function bootGame(version)
  -- The launcher hands us the chosen game (Red / Blue); scripted and headless
  -- runs fall back to POKEPORT_VERSION, then Red.  Set the active version and
  -- overlay its extracted cache BEFORE anything requires generated data, so
  -- data/generated + assets/generated resolve to that version's files.
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version or os.getenv("POKEPORT_VERSION") or "red")
  bootLog("starting " .. GameVersion.get())
  local mounted = require("src.import.CacheFs").mountVersion(GameVersion.get())
  bootLog("cache mount: " .. tostring(mounted))
  if love.window and love.window.setTitle then
    local Version = require("src.core.Version")
    love.window.setTitle(Version.title(
      GameVersion.info().displayName .. " (Gen 1 Recompilation Project)"))
  end
  Game = require("src.core.Game")
  bootLog("core loaded; initializing game")
  Game:load()
  bootLog("game initialized")
  OpenXR.init()
  if os.getenv("POKEPORT_AUTOPILOT") then
    autopilot = require("tests.autopilot")
  end
  local driverPath = os.getenv("POKEPORT_DRIVER")
  if driverPath then
    local fn = assert(loadfile(driverPath))()
    driverCo = coroutine.create(fn)
  end
  -- After the two above are known: a scripted run drives the multiplier
  -- from love.update's loop, so the in-engine one must stay at 1 or the
  -- two would compound (10x10 = 100 steps per observation).
  Game.speedOverride = (autopilot or driverCo) and 1 or speedOverride
end

local function tryBootGame(version)
  local ok, err = xpcall(function() bootGame(version) end, debug.traceback)
  if ok then return true end
  Game = nil
  bootLog("FAILED: " .. tostring(err), 6)
  pcall(love.filesystem.write, "quest-boot-error.txt", tostring(err))
  return false, err
end

function love.load(args)
  -- Self-updater boot shell: a fused build may mount and chainload a newer
  -- downloaded payload here.  True means it took over, so we must stop.  A
  -- dev / source checkout no-ops (see src/update/Boot.lua).
  local Boot = require("src.update.Boot")
  if Boot.run(args) then return end
  OpenXR.configure(args)
  -- Do not initialize Quest OpenXR from love.load.  On some Quest firmware
  -- revisions the Android activity and EGL context are not fully ready yet;
  -- one transient failure here used to leave the headset on its loading dots
  -- forever.  love.draw calls beginFrame, which starts XR once the graphics
  -- context is current and retries safely if the runtime is still starting.

  local savePath
  for i, a in ipairs(args or {}) do
    if a == "--editor" then
      editorMode = true
    elseif a == "--developer" then
      _G.POKEPORT_DEV_MODE = true
    elseif a == "--save" and args[i + 1] and args[i + 1] ~= "" then
      savePath = args[i + 1]
    elseif a == "--speed" and tonumber(args[i + 1]) then
      speedOverride = tonumber(args[i + 1])
    end
  end
  love.graphics.setDefaultFilter("nearest", "nearest")

  if editorMode then
    package.path = love.filesystem.getSource() .. "/tools/save-editor/?.lua;"
                .. love.filesystem.getSource() .. "/tools/save-editor/panels/?.lua;"
                .. package.path
    EditorApp = require("App")
    EditorApp.load(savePath)
    return
  end

  local RomImporter = require("src.import.RomImporter")
  local forceImport = os.getenv("POKEPORT_FORCE_IMPORT") == "1"
  local importPath = os.getenv("POKEPORT_IMPORT_ROM")
  -- Scripted / headless runs pick their game from POKEPORT_VERSION (default
  -- Red); the launcher's per-column choice does not apply to them.
  local scriptedVersion = os.getenv("POKEPORT_VERSION") or "red"
  local ready = RomImporter.isReady(scriptedVersion)
  -- Scripted / headless runs have to reach the game with no human pressing
  -- Play: an autopilot, a frame driver, an import-only build step, or an
  -- explicit ROM path all bypass the interactive launcher and keep today's
  -- import-then-boot (or boot-straight-in) behavior.
  local scripted = os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER")
    or os.getenv("POKEPORT_IMPORT_ONLY") == "1" or importPath ~= nil

  if scripted then
    if forceImport or not ready then
      -- The importer detects the dropped/loaded ROM's version by SHA-1 and
      -- passes it to onComplete; boot that version.
      Importer = RomImporter.new(function(version)
        if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then
          love.event.quit()
          return
        end
        if tryBootGame(version or scriptedVersion) then Importer = nil end
      end)
      if importPath then Importer:startPath(importPath) end
      return
    end
    tryBootGame(scriptedVersion)
    return
  end

  -- Interactive: the launcher always runs.  Red and Blue are each live: a
  -- column shows Play when that game's ROM is already imported, or Choose ROM
  -- / drag-drop when it is not (Yellow is still a placeholder).  Any dropped
  -- .gb is routed to Red or Blue by its SHA-1; pressing Play boots that game.
  Importer = RomImporter.new(function(version)
    local launcher = Importer
    local ok, err = tryBootGame(version)
    if ok then
      Importer = nil
    else
      -- Keep the spatial launcher alive and make the failure visible instead
      -- of falling through to LÖVE's flat error screen / Quest Home.
      launcher._handedOff = false
      launcher.workState = "error"
      launcher.errorVersion = version or "red"
      launcher.status = "Pokemon could not start"
      launcher.detail = tostring(err):match("^[^\n]+") or tostring(err)
      launcher.progress = 0
    end
  end, { launcher = true, forceImport = forceImport })
end

function love.update(dt)
  if editorMode then return EditorApp.update(dt) end
  if Importer then
    -- A VR pointer press can synchronously hand off to the game and clear the
    -- global Importer below. Keep the current launcher in a local and only
    -- update it if the handoff did not happen during this same frame.
    local launcher = Importer
    if OpenXR.isQuestBuild() then
      if not OpenXR.syncInput(nil, dt) then
        if love.timer and love.timer.sleep then love.timer.sleep(0.10) end
        return
      end
      local pointer = OpenXR.pointer()
      local down = pointer.active and pointer.down
      local w, h = love.graphics.getDimensions()
      if launcher.setVRPointer then
        launcher:setVRPointer(pointer.active and pointer.x * w or nil,
                              pointer.active and pointer.y * h or nil)
      end
      if down and not importerPointerDown and launcher.mousepressed then
        launcher:mousepressed(pointer.x * w, pointer.y * h, 1)
      end
      importerPointerDown = down
    end
    if Importer == launcher then return launcher:update(dt) end
    return
  end

  -- OpenXR actions are independent from LOVE/SDL gamepad events. Poll them
  -- before the fixed step so VR controllers drive menus and gameplay with
  -- the same latency and edge semantics as every other input source.
  local xrInputReady = OpenXR.syncInput(Game and Game.input, dt)
  if OpenXR.isQuestBuild() and not xrInputReady then
    -- SDL/Android can leave the Lua loop alive briefly after the Quest shell
    -- takes immersive focus. Do no game simulation or remeshing in that
    -- state, and throttle the residual event loop so Android never sees a
    -- background process burning sustained CPU.
    if love.timer and love.timer.sleep then love.timer.sleep(0.10) end
    return
  end
  require("src.vr.Pointer").update(Game)

  -- Scripted runs (autopilot / POKEPORT_DRIVER) observe and act exactly
  -- once per Game:update, so they must keep a 1:1 relationship with the
  -- logic step.  Fast-forwarding them by scaling the step inside
  -- Game:update would run N steps per observation: a held direction walks
  -- through all N, the player slides past the waypoint, and the script
  -- re-plans from an overshot cell.  So iterate the whole act+step loop
  -- instead -- same script, just more of it per rendered frame.
  local iterations = scriptedIterations()

  if autopilot then
    for _ = 1, iterations do
      autopilot.update()
      Game:update(1 / 60) -- deterministic stepping for the autopilot
    end
    return
  end
  if driverCo then
    for _ = 1, iterations do
      local ok, err = coroutine.resume(driverCo, Game)
      if not ok then
        print("driver error: " .. tostring(err))
        love.event.quit(1)
        return
      end
      if coroutine.status(driverCo) == "dead" then
        love.event.quit()
        return
      end
      Game:update(1 / 60)
    end
    return
  end
  Game:update(dt)
end

function love.draw()
  if editorMode then return EditorApp.draw() end
  if Importer then
    if OpenXR.isQuestBuild() and not OpenXR.beginFrame() then return end
    Importer:draw()
    if OpenXR.isQuestBuild() then
      local pointer = OpenXR.pointer()
      if pointer.active then
        local w, h = love.graphics.getDimensions()
        local x, y = pointer.x * w, pointer.y * h
        love.graphics.push("all")
        love.graphics.setColor(1, 1, 1, 1)
        -- A visible white laser plus a high-contrast target. The line starts
        -- at the lower-right edge of the launcher and ends on the selected
        -- button, matching the in-game menu pointer language.
        love.graphics.setLineWidth(5)
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.line(w - 1, h - 1, x, y)
        love.graphics.setLineWidth(3)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.line(w - 1, h - 1, x, y)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.circle("fill", x, y, pointer.down and 12 or 10)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.circle("fill", x, y, pointer.down and 8 or 7)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.circle("fill", x, y, 2)
        love.graphics.pop()
      end
    end
    if OpenXR.isActive() then
      local w, h = love.graphics.getPixelDimensions()
      -- captureUI reads the Android framebuffer immediately. LÖVE may still
      -- have the last few batched primitives pending here (notably the VR
      -- laser/cursor, which is drawn last), making interaction work while the
      -- pointer itself stays invisible in the headset.
      if love.graphics.flushBatch then love.graphics.flushBatch() end
      OpenXR.captureUI(w, h)
      -- The launcher is a spatial quad only. Submitting its flat Android
      -- framebuffer as a projection as well produced a duplicate head-locked
      -- menu split across both eyes on Quest.
      OpenXR.submitFrame(false)
    end
    return
  end

  local xrFrameReady = OpenXR.beginFrame()
  if OpenXR.isQuestBuild() and not xrFrameReady then return end
  Game:draw()
  OpenXR.submitFrame()
  -- frame capture requested by a driver
  if Game.capturePath then
    local path = Game.capturePath
    Game.capturePath = nil
    love.graphics.captureScreenshot(function(imagedata)
      local fd = imagedata:encode("png")
      local f = io.open(path, "wb")
      if f then
        f:write(fd:getString())
        f:close()
      end
    end)
  end
end

function love.keypressed(key, scancode, isrepeat)
  if editorMode then return EditorApp.keypressed(key) end
  if Importer then return Importer:keypressed(key) end
  if key == "f8" and OpenXR.requested() then
    OpenXR.recenter()
    return
  end
  Game:keypressed(key)
end

function love.keyreleased(key)
  if editorMode then return end
  if Importer then return end
  Game:keyreleased(key)
end

function love.gamepadpressed(joystick, button)
  if editorMode then return end
  if Importer then return end
  Game:gamepadpressed(joystick, button)
end

function love.gamepadreleased(joystick, button)
  if editorMode then return end
  if Importer then return end
  Game:gamepadreleased(joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
  if editorMode then return end
  if Importer then return end
  Game:gamepadaxis(joystick, axis, value)
end

function love.joystickremoved(joystick)
  if editorMode then return end
  if Importer then return end
  Game:joystickremoved(joystick)
end

-- f is true on focus gained, false on focus lost (e.g. alt-tab). A held
-- direction's key-up can be delivered to the OS instead of the game while
-- unfocused, so reset input on either transition rather than trust it.
function love.focus(f)
  if editorMode then return end
  if OpenXR.isQuestBuild() then OpenXR.setActivityFocused(f) end
  if Importer then
    if Importer.focus then Importer:focus(f) end
    return
  end
  Game:focus(f)
end

-- v is true when the window becomes visible again, false while a Quest
-- system panel or another Android surface is covering it. Visibility loss is
-- temporary: keep the OpenXR instance/session alive and let its lifecycle
-- events move it through VISIBLE/STOPPING. Full shutdown belongs to love.quit.
function love.visible(v)
  if editorMode then return end
  if OpenXR.isQuestBuild() then OpenXR.setActivityFocused(v) end
  if Importer then return end
  Game:visible(v)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  if editorMode then return end
  if Importer then return Importer:mousepressed(x, y, 1) end
  Game:touchpressed(id, x, y)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
  if editorMode then return end
  if Importer then return end
  Game:touchmoved(id, x, y)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  if editorMode then return end
  if Importer then return end
  Game:touchreleased(id, x, y)
end

function love.wheelmoved(x, y)
  if editorMode then
    if EditorApp.wheelmoved then return EditorApp.wheelmoved(x, y) end
    return
  end
  if Importer then return end
  Game:wheelmoved(x, y)
end

function love.mousepressed(x, y, button)
  if Importer then return Importer:mousepressed(x, y, button) end
  if editorMode and EditorApp.mousepressed then
    return EditorApp.mousepressed(x, y, button)
  end
  if mouseTouch and Game and button == 1 then
    Game:touchpressed("mouse", x, y)
  end
end

function love.mousereleased(x, y, button)
  if Importer then return end
  if editorMode and EditorApp.mousereleased then
    return EditorApp.mousereleased(x, y, button)
  end
  if mouseTouch and Game and button == 1 then
    Game:touchreleased("mouse", x, y)
  end
end

function love.mousemoved(x, y)
  if editorMode or Importer then return end
  if mouseTouch and Game and love.mouse.isDown(1) then
    Game:touchmoved("mouse", x, y)
  end
end

function love.textinput(text)
  if Importer then return end
  if editorMode and EditorApp.textinput then
    return EditorApp.textinput(text)
  end
end

function love.quit()
  if editorMode and EditorApp.quit then
    return EditorApp.quit() -- return true to abort quit
  end
  OpenXR.shutdown()
  pcall(function()
    require("src.core.DiscordPresence").shutdown()
  end)
end

function love.filedropped(file)
  if editorMode and EditorApp and EditorApp.filedropped then
    return EditorApp.filedropped(file)
  end
  if Importer then Importer:filedropped(file) end
end

local function pacingEnabled()
  if os.getenv("POKEPORT_AUTOPILOT") then return false end
  if os.getenv("POKEPORT_DRIVER") then return false end
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then return false end
  return true
end

function love.run()
  if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

  -- don't let love.load's cost land in the first frame's dt
  if love.timer then love.timer.step() end

  local FrameCap = require("src.core.FrameCap")
  local paced = pacingEnabled()
  -- The deadline the next present() should not beat.  Carried forward one
  -- budget per frame so pacing stays even instead of drifting with the
  -- per-frame sleep-granularity jitter.
  local nextFrame = love.timer and love.timer.getTime() or 0
  local dt = 0

  return function()
    -- process events
    if love.event then
      love.event.pump()
      for name, a, b, c, d, e, f in love.event.poll() do
        if name == "quit" then
          if not love.quit or not love.quit() then
            return a or 0
          end
        end
        love.handlers[name](a, b, c, d, e, f)
      end
    end

    -- update dt
    if love.timer then dt = love.timer.step() end

    -- call update and draw
    if love.update then love.update(dt) end

    if love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      if love.draw then love.draw() end
      love.graphics.present()
    end

    if love.timer then
      local xrPaced = OpenXR.ownsPacing and OpenXR.ownsPacing()
      if paced and not xrPaced then
        -- Sleep out the remainder of the frame budget, measured from the
        -- carried deadline, in small chunks so the OS timer stays
        -- responsive. In focused VR, xrWaitFrame is already the exact
        -- headset clock and this limiter must stay completely out of its way.
        local budget = 1 / FrameCap.current
        nextFrame = nextFrame + budget
        local now = love.timer.getTime()
        -- A stall (alt-tab, a GC pause, a blocked import) can leave the
        -- deadline more than a full budget in the past; re-anchor to now so
        -- we pace the next frame rather than burst uncapped to catch up.
        if now - nextFrame > budget then
          nextFrame = now
        end
        while true do
          local remaining = nextFrame - love.timer.getTime()
          if remaining <= 0 then break end
          love.timer.sleep(remaining < 0.001 and remaining or 0.001)
        end
      elseif xrPaced then
        -- Prevent a stale desktop deadline from causing a catch-up burst if
        -- the system menu temporarily takes XR focus and returns it later.
        nextFrame = love.timer.getTime()
      else
        love.timer.sleep(0.001)
      end
    end
  end
end
