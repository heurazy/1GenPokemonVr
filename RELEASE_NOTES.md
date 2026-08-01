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
