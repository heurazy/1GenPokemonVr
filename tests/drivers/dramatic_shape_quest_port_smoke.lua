-- Smoke test for the official v1.5.4 + standalone Quest integration.
-- Runs on desktop: QuestVR remains dormant, while the shared official
-- modules, shaders and render-pipeline registration are exercised.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")
  local handle = assert(game.mods.exports.DRAMATIC_SHAPE,
                        "DRAMATIC_SHAPE export missing")
  assert(handle.version == "1.5.4-quest.5",
         "unexpected Dramatic Shape version: " .. tostring(handle.version))
  assert(handle.lib and handle.lib.require,
         "Dramatic Shape module namespace missing")

  local quest = handle.lib.require("QuestVR")
  assert(quest and quest.supported and quest.active,
         "Quest adapter did not load")
  assert(quest.supported() == false,
         "desktop smoke run must not claim the Quest runtime")

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  Pipelines.setLevel("voxel", 3)
  Pipelines.syncOptions(game.save.options)
  U.wait(120)

  local defs = game.data.render_pipelines or {}
  assert(defs.voxel and defs.voxel.available and defs.voxel.available(),
         "official voxel pipeline is unavailable")
  assert(game.renderer.worldOverride,
         "voxel world override was not produced")
  print("[dramatic-shape-quest] desktop smoke OK")
end
