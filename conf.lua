function love.conf(t)
  local editor = os.getenv("POKEPORT_EDITOR") == "1"
  local developer = os.getenv("POKEPORT_DEV") == "1"
  local vr = os.getenv("GEN1RECOMP_VR") == "1"
  local quest = love.filesystem and love.filesystem.getInfo
    and love.filesystem.getInfo("quest_build.txt") ~= nil
  if quest then vr = true end
  if arg then
    for _, a in ipairs(arg) do
      if a == "--editor" then editor = true end
      if a == "--developer" then developer = true end
      if a == "--vr" then vr = true end
      if a == "--no-vr" then vr = false end
    end
  end
  -- main.lua runs in the same Lua state right after conf.lua; stash the
  -- decision in a global so it doesn't need to reparse `arg`.
  _G.POKEPORT_EDITOR_MODE = editor
  _G.POKEPORT_DEV_MODE = developer

  if editor then
    t.identity = os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d-editor"
    t.window.title = "Pokemon Save Editor"
    t.window.width = 1280
    t.window.height = 800
  else
    t.identity = os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d"
    -- Version.lua has zero requires, so it is loadable this early; fall
    -- back to the plain title if the source is not mounted yet
    local ok, Version = pcall(require, "src.core.Version")
    t.window.title = ok and Version.title()
      or "gen1recomp"
    -- Open at the launcher's design size (the split-screen ROM selector is
    -- laid out for 1024x768). The window is resizable and the 160x144 game
    -- canvas letterboxes into whatever size it ends up, so this only sets the
    -- starting size, not the game's resolution.
    -- The OpenXR bridge submits the left and right halves of this mirror
    -- window as distinct projection views.  Establish the wide framebuffer
    -- before the bridge binds the OpenGL context; resizing afterwards can
    -- recreate that context on some SDL drivers.
    t.window.width = vr and 2880 or 1024
    t.window.height = vr and 1600 or 768
  end
  t.version = "11.5"
  -- xrWaitFrame owns pacing in VR; desktop vsync would add a second wait.
  t.window.vsync = vr and 0 or 1
  t.modules.joystick = true
  t.modules.physics = false

  -- love.system is not loaded during love.conf; love._os is set by the
  -- engine before conf runs (LÖVE 11.x / 11.5).
  local osName = love._os
  local mobile = osName == "Android" or osName == "iOS"
  if mobile and quest then
    -- Quest needs the stereo-sized landscape framebuffer before OpenXR binds
    -- the existing EGL context.  The generic Android portrait defaults used
    -- to replace the VR dimensions and could prevent a valid first XR frame.
    t.window.resizable = false
    t.window.width = 2880
    t.window.height = 1600
    t.window.fullscreen = true
    t.window.highdpi = true
    t.externalstorage = true
  elseif mobile then
    -- resizable is what unlocks orientation.  SDL's Android backend, given no
    -- SDL_HINT_ORIENTATIONS (LÖVE sets none), calls setRequestedOrientation
    -- at window creation -- FULL_SENSOR when the window is resizable (rotates
    -- freely to portrait or landscape), otherwise locked to the window's w/h
    -- aspect.  So a non-resizable tall window forced portrait; resizable lets
    -- the game follow the device.  The renderer letterboxes the 160x144
    -- viewport into whatever size results, and the on-screen touch controls
    -- re-lay themselves out from the new window size, so both orientations
    -- just work.  iOS follows the Info.plist orientations
    -- (see mobile/ios/overlays/love-ios.plist, now portrait + landscape).
    t.window.resizable = true
    -- Starting size is a tall portrait hint; the OS resizes to the real
    -- display and rotations resize again. highdpi is required for Retina iOS
    -- (Android always behaves as highdpi).
    t.window.width = 1080
    t.window.height = 1920
    t.window.fullscreen = true
    t.window.highdpi = true
    -- Android only (irrelevant on iOS): puts the save directory under the
    -- app's external-files folder, which is readable/writable via USB or a
    -- file manager with no runtime permission, so RomImporter can ask the
    -- player to copy their ROM there instead of needing a native file
    -- picker (LOVE 11.5 on Android has none -- see src/import/RomImporter.lua).
    t.externalstorage = osName == "Android"
  else
    t.window.resizable = true
  end
end
