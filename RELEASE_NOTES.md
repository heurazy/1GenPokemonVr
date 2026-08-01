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
