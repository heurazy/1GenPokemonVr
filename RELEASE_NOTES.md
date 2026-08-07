# 1GenPokemonVR v0.2.39 — Quest 3 performance and high-refresh release

This release consolidates the standalone Quest 3/3S VR work through v0.2.39.
It remains ROM-free: the APK contains no Pokemon ROM or pre-extracted game
assets and asks the player for a legally obtained compatible US Red or Blue
ROM on first launch.

## Quest rendering

- Native per-eye OpenXR stereo rendering with 6DoF head tracking and Meta
  Touch/Touch Plus controller support.
- First-person Dramatic Shape voxel world with the tracked left-hand
  Pokedex/tablet used for menus, dialogs and battle UI.
- Adjustable Quest draw distance: **20 / 24 / 28 / 32 / 36 m**, with 28 m as
  the balanced default.
- Quest render quality presets: **50 / 60 / 75 / 85 / 100%** per-eye scale.
- Shadows are disabled by default on standalone Quest and remain available as
  an explicit VR option.
- Water uses the lighter SKY reflection path by default; the unnecessary
  full-eye reflection copy is skipped in that mode.

## Performance work

- Tall grass is split into spatial chunks and culled outside a tight headset
  view cone and useful distance range.
- Redundant grass back faces and top strips are removed on Quest.
- Distant NPCs, authored figures and connected-map detail outside the view are
  rejected before their draw calls.
- Terrain vertical geometry is separated by face direction (north/south/east/
  west), allowing whole groups of walls facing away from the headset to be
  skipped before GPU submission.
- Connected maps behind the player are still prefetched but are no longer
  submitted to both eyes when they are safely outside the visible region.
- The software MAX FPS limiter is bypassed while OpenXR owns frame pacing, so
  `xrWaitFrame` is the single VR presentation clock.

## High refresh rate

- Added native `XR_FB_display_refresh_rate` support on Quest.
- New **VR OPTION -> DISPLAY RATE** setting with **72 / 80 / 90 / 120 Hz**.
- **90 Hz** is the standalone default. If the requested rate is unavailable,
  the bridge selects the nearest refresh rate reported by the runtime.
- Game simulation remains fixed at 60 ticks/s for timing compatibility while
  headset pose, controllers and stereo presentation can update at the selected
  display rate.

## Fixes and polish

- Main OPTION menu VR pointer clicks are now one-shot and no longer double
  activate through the synthetic Game Boy A input path.
- Transparent Pokedex/tablet screen keeps the live UI readable without an
  opaque black rectangle.
- Quest pause/resume, recenter and temporary OpenXR visibility loss recovery
  were hardened across the recent builds.
- 64/64 Windows regression suites pass for this release candidate.

## Quest APK

`1GenPokemonVR-Quest3-v0.2.39.apk`

SHA-256:
`04FE3A913E677C1C73C089423F0195AE5ECA2B05102F7B9BC890DAB8E97ABEEB`

---

# 1GenPokemonVR v0.2.14 — Quest launch and package identity hotfix

- Declares the baseline Horizon OS SDK level expected by current Quest
  firmware, preventing invalid framework-manager access during startup.
- Quest builds now pass their version directly to Gradle and verify the
  generated APK identity before publishing it, so a newly named release can
  no longer contain the previous Android package version.

# 1GenPokemonVR v0.2.13 — First-person Quest and true 3D battles

- Quest now boots into Dramatic Shape's official `1ST` first-person mode,
  including the mod's free-movement and headset-facing interaction logic.
- Restored the official handheld Pokedex/tablet as tracked geometry on the
  left Touch controller. Dialogs, menus and the battle interface appear on
  its screen instead of a gaze-following flat panel.
- Connected the standalone OpenXR bridge to Dramatic Shape's real two-eye
  renderer. Battles now use the staged voxel arena and independent eye
  cameras instead of one mono image duplicated in front of the headset.
- Quest battles now inherit the official VR battle policy: both Pokemon stay
  in the arena, the battle camera remains stable, and fallback flat battle
  layers are suppressed whenever the handheld display is active.

# 1GenPokemonVR v0.2.12 — Official Dramatic Shape 1.5.4 Quest port

- Rebased the bundled voxel mod on the official Dramatic Shape v1.5.4 release
  while preserving the earlier standalone OpenXR work in `backups/`.
- Added the engine-owned Quest stereo adapter: official per-eye voxel renders,
  physical IPD preservation, a 0.75 default render scale and a mobile-first
  quality profile without removing any official gameplay mode.
- Reduced headset-frame Lua garbage by reusing the per-eye pose, FOV, camera
  matrices/vectors, view descriptors and stereo result list, while caching the
  immutable Quest render-scale override.
- Scripted trainer and wild fights now enter through the overworld transition,
  restoring the flash/wipe, battle-music timing and Dramatic Shape arena setup.
- Quest packaging excludes desktop OpenXR binaries, tests, documentation and
  development artifacts while retaining the full official runtime mod. The
  installable release APK now packages only the ARM64 libraries Quest can
  execute.

# 1GenPokemonVR v0.2.9 — Pointer and clean voxel world

- NEW GAME and other generic menus now receive VR pointer clicks directly.
- Standalone VR forces the Dramatic Shape V-GRID wireframe off, removing the
  dense black diagonal seams projected across the 3D world.

# 1GenPokemonVR v0.2.8 — Upright in-game menus

- Fixed the vertical orientation of in-game UI captured from LÖVE canvases.
- Pointer coordinates now match the visible menu rows, preventing NEW GAME
  from accidentally activating EXIT GAME.
- Applied the same Canvas correction to spatial battle and HUD layers.

# 1GenPokemonVR v0.2.7 — Play button crash fix

- Fixed the Quest-only crash immediately after pressing Play: the VR pointer
  update no longer accesses the launcher after it has handed off to the game.
- Retains the guarded game boot and Android diagnostics introduced in 0.2.6.

# 1GenPokemonVR v0.2.6 — Safe Quest game boot

- The Play button now keeps the spatial launcher alive if game initialization
  fails instead of dropping into a flat LÖVE error screen or Quest Home.
- Added step-by-step `Gen1PokemonVR` Android logging for ROM-cache mounting,
  core loading and game initialization.
- A complete Lua traceback is also saved as `quest-boot-error.txt` after a
  failed boot, making device-only failures diagnosable.

# 1GenPokemonVR v0.2.5 — Launcher VR pointer

- Added a visible white controller ray and target to the pre-game launcher.
- Launcher buttons now highlight under the VR pointer and accept either the
  right trigger or A.
- Added a head-gaze pointer fallback while the Quest controller aim pose is
  waking up, so the launcher never becomes pointerless.

# 1GenPokemonVR v0.2.4 — Quest presentation and controls hotfix

- Removed the duplicate head-locked launcher projection. The launcher is now
  submitted once as a spatial OpenXR panel.
- Fixed vertically inverted OpenXR UI and battle layers on Quest.
- Enabled the Meta Touch Plus interaction profile used by Quest 3 and 3S,
  including tracked aim, trigger pointer, buttons and both thumbsticks.

# 1GenPokemonVR v0.2.3 — Quest JNI lifetime hotfix

- Fixed the immediate Quest crash caused by passing a temporary Android JNI
  activity reference to the OpenXR loader. The activity is now kept valid for
  every loader call and for delayed initialization retries.

# 1GenPokemonVR v0.2.2 — Quest native loader hotfix

- Fixed Quest startup after an on-device ADB trace showed that LÖVE's SDL JNI
  helpers were loaded with local symbol visibility. The OpenXR bridge now
  resolves them explicitly from the already-loaded `liblove.so`.
- Retains the deferred initialization, cleanup and retry safeguards introduced
  in v0.2.1.

# 1GenPokemonVR v0.2.1 — Quest startup hotfix

- Fixed the endless Quest loading dots caused by OpenXR being initialized
  before Android's activity and EGL context were fully ready.
- OpenXR now starts from the first rendered frame, cleans up partial native
  initialization, and retries with a bounded delay after transient failures.
- Quest builds now select their stereo landscape framebuffer and disable
  desktop/mobile double pacing directly from `conf.lua`.
- The native bridge no longer treats an instance without a valid session as a
  successful initialization.

This is still a hardware preview: the ARM64 APK, native bridge, package,
signature and embedded payload were validated locally, but a physical Quest
was not connected to this build environment for the final headset test.

# 1GenPokemonVR v0.2.0 — Quest 3 standalone preview

## New

- Standalone, ROM-free Meta Quest 3/3S APK (`arm64-v8a`).
- Native Android OpenXR/OpenGL ES bridge using the official Khronos loader.
- **VR OPTION -> ENVIRONMENT -> AR PASSTHROUGH** places the voxel world over
  the real room through Meta color passthrough.
- The first-run ROM chooser is presented as a spatial OpenXR panel and accepts
  the right Touch controller ray.
- The same spatial battles, VR menu pointer, camera modes and world placement
  controls from the Windows build are included.

## Preview status

The APK builds, signs and passes structural validation. It includes the
immersive HMD manifest category, Quest 3/3S metadata, ARM64 LÖVE runtime,
`libgen1openxr.so`, `libopenxr_loader.so` and a ROM-free `game.love` payload.
A physical-headset comfort/performance pass is still required before calling
this a stable Quest release.

## Install

1. Enable Developer Mode on the Quest.
2. Install the APK with Meta Quest Developer Hub or `adb install -r`.
3. Open **Library -> Unknown Sources -> 1GenPokemonVR Quest**.
4. Select a legally obtained compatible US Pokémon Red or Blue ROM.

---

# 1GenPokemonVR v0.1.0

This is the first OpenXR preview distribution candidate of 1GenPokemonVR.

## Highlights

- Native per-eye OpenXR voxel rendering and 6DoF head tracking.
- Four VR camera modes: Immersive, Orbit, Overhead and First Person.
- Expanded VR settings for world scale, camera distance, pitch, height,
  horizontal placement, head-motion strength and comfort turning.
- Head-relative first-person locomotion while retaining the original game's
  cardinal movement, collision and event logic.
- Ray pointer input and persistent draggable scrollbars for long menus.
- Spatial battles with distinct opponent, attack and player depths.
- Foreground battle HUD for unobstructed names, status and HP information.

## Installation

1. Extract the Windows archive into a new folder.
2. Start SteamVR or another working Windows OpenXR runtime.
3. Connect the headset and controllers.
4. Run `LAUNCH-1GEN-POKEMON-VR.bat`.
5. Provide a legally obtained canonical US Pokemon Red or Blue ROM when the
   game asks for it. No ROM or extracted game data is included.

Use **START -> VR OPTION** in game to configure the camera. Press `F8` to
recenter the world and interface.

## Credits

- Engine: [bryanthaboi/gen1recomp](https://github.com/bryanthaboi/gen1recomp)
- Voxel-world foundation: [Dramatic Shape Voxel Mod v1.4.0](https://github.com/DramaticShape/DramaticShapeVoxelMod/releases/tag/v1.4.0)

See `THIRD_PARTY_NOTICES.md` for redistribution requirements.
