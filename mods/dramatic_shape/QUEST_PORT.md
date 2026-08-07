# Standalone Quest port

This directory is based on the official `DramaticShapeVoxelMod` v1.5.4 tag.
The original local v1.1.0 VR work is preserved outside the packaged mod in
`backups/dramatic_shape-1.1.0-vr-before-official-v1.5.4`.

`lib/QuestVR.lua` does not create an OpenXR session. The Android application
already owns the session through `src/vr/OpenXR.lua` and the native
`libgen1openxr.so` bridge. The adapter converts its two predicted eye poses
to the official `VRRig.eyeCamera` records, invokes the official two-eye
`VoxelScene.render` path, then composites the result side by side for the
native bridge.

The Quest adapter preserves the physical inter-eye distance at every HEAD
MOTION setting, restores the previous graphics target even after a driver
error, and returns all temporary stereo state to the official renderer after
each frame. Generic Android builds retain the official shadow-map capability
probe; only the standalone Quest profile selects the cheaper decal fallback.
The hot stereo path also reuses its pose, field-of-view, camera matrix/vector,
eye descriptor and returned canvas-list tables, and caches the immutable
render-scale override. This avoids rebuilding a large short-lived Lua object
graph at headset refresh rates.

The first-run Quest profile now selects the official `1ST` camera and free-move
implementation. The tracked left controller carries the official handheld
Pokedex; menus, dialogs and battles appear on its screen as real, depth-tested
geometry. The profile also disables tilt-shift, wireframe and supersampling,
selects SKY-only water reflections, and keeps a light world curve. Android uses
the official decal shadow fallback in place of the extra shadow-map pass. Set
`GEN1RECOMP_QUEST_VOXEL_SCALE` between `0.5` and `1.0` to override the default
0.75 per-eye render scale.

Desktop PCVR remains the official v1.5.4 implementation. Its Win32 loader and
development files stay in the source tree but are excluded from Quest APKs by
`scripts/build-quest.ps1`.

This Quest engine branch predates the optional 304x144 WideBattle compositor.
It therefore exposes only the classic 160x144 battle surface that Dramatic
Shape requires for staged fights; the port does not add a dead BATTLE LAYOUT
switch. Script-driven fights are routed through the overworld transition seam,
so they receive the same wipe, music timing and VR arena preparation as grass
and trainer-sight encounters.
