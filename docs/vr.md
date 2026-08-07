# OpenXR / SteamVR mode

For standalone Quest 3/3S installation, see
[`quest.md`](quest.md).

This branch adds native stereo VR to the Dramatic Shape voxel overworld.
It is not a duplicated cinema screen:

- terrain and characters render once per eye;
- each eye uses the runtime-provided asymmetric field of view;
- the headset pose drives the world camera with 6DoF translation and
  rotation;
- each eye owns an independent color target and depth buffer;
- the native bridge submits both images as an OpenXR projection layer.

Battles, the title screen and full-screen menus remain the original 2D
presentation. Menus and dialogs are submitted as one OpenXR quad layer,
anchored in the world so both eyes converge on the same physical panel.

## Requirements

- Windows 10 or 11, x64
- SteamVR with SteamVR selected as the active OpenXR runtime
- a PC VR headset recognized by SteamVR
- LÖVE 11.5 x64
- Visual Studio 2022 C++ Build Tools
- CMake 3.21 or newer
- Git (the first bridge build bootstraps vcpkg and OpenXR Loader)
- a legally obtained canonical US Pokémon Red or Blue ROM

In SteamVR, open **Settings → OpenXR** and select **Set SteamVR as OpenXR
Runtime** if another runtime is active.

## Build and launch

1. Run `Play-Windows.bat` once and import your ROM.
2. Start SteamVR and connect the headset.
3. Double-click `Play-VR.bat`.

The first VR launch runs `scripts/build-vr.ps1`. It downloads vcpkg into the
ignored `.vr-deps` directory, installs the official Khronos OpenXR Loader and
builds `native/openxr_bridge/bin/gen1openxr.dll`. Later launches reuse it.

From PowerShell:

```powershell
.\scripts\build-vr.ps1
.\scripts\run-vr.ps1
```

## VR controllers

OpenXR controllers are detected automatically. The bridge includes semantic
bindings for Meta/Oculus Touch, Valve Index, HTC Vive wands, Windows Mixed
Reality and the Khronos simple-controller fallback; compatible devices
emulated by SteamVR use the corresponding OpenXR profile.

- left stick or trackpad: move (menu navigation is disabled while a ray menu
  is open);
- right A / trigger: Game Boy A (confirm/interact);
- right B / grip: Game Boy B (cancel);
- menu: START; left face/menu: SELECT;
- right stick/trackpad: orbit or comfort turn;
- right stick click: recenter headset, UI and camera orbit.
- aim the right controller at a menu to show the pointer; hover a row and
  squeeze the trigger to select it. The pointer is hidden outside interactive
  menus and during battle animations or ordinary dialogue.

When a menu supports the pointer, all controller-stick menu navigation is
disabled to prevent double movement. Every long list has a persistent,
browser-style scrollbar on its right edge. Aim at its track, hold the trigger
and drag the thumb to any position. The high-contrast white laser and cursor
remain visible for the whole time an interactive menu is open.

Battles use several aligned OpenXR planes at a fixed LOCAL-space anchor. The
battlefield is farthest away, the opposing Pokemon sits deeper in the scene,
attacks occupy an intermediate plane, and the player's Pokemon is closest.
Names, status and HP bars use a high-contrast foreground plane that is submitted
after Pokemon, attacks and menus, so important information stays unobstructed.
Commands and text remain on their own menu layer. Entering a battle establishes
a new anchor, and F8 recenters every battle layer together.

Keyboard and conventional gamepads remain available at the same time.

## Controls and tuning

- The Pokemon **START -> VR OPTION** page, directly below OPTION, selects
  IMMERSIVE (the original
  default), Animal Crossing-style ORBIT, OVERHEAD or FIRST PERSON cameras.
  It also controls world scale, view distance, pitch, height, X/Z placement,
  head-motion strength, smooth/snap/off turning and snap angle.
- In FIRST PERSON, pushing the left stick forward follows the horizontal
  direction of the headset. Movement remains snapped to the four directions
  used by the original game, so collision and scripts are unchanged.
- `F8` recenters the headset pose and places the menu at a new fixed anchor
  upright at eye height in front of you. Looking up or down while pressing
  F8 does not tilt the panel or move it below the player.
- `3` cycles the base diorama pitch.
- `5` toggles voxel grid lines.
- `6` cycles tilt-shift. It starts disabled in VR because of its GPU cost.
- `7` cycles the curved-world effect.

The default world scale is 64 game pixels per physical metre. Override it
before launch if the miniature feels too large or too small:

```powershell
$env:GEN1RECOMP_VR_SCALE = '80'
.\scripts\run-vr.ps1
```

## Runtime architecture

`src/vr/OpenXR.lua` calls the bridge through LuaJIT FFI. At the start of a
frame the bridge runs `xrWaitFrame`, locates both views and exposes their
poses/FOVs to Lua. The voxel renderer builds two OpenGL canvases. At the end
of the frame the bridge blits the left and right halves of LÖVE's mirror
framebuffer into runtime-owned OpenGL swapchains. UI and battle canvases go
to separate alpha-enabled quad swapchains whose poses remain fixed in OpenXR
LOCAL space, then all active layers are submitted together through
`xrEndFrame`.

If `--vr` is not supplied, the DLL is missing, or the platform is not
Windows, all VR calls are no-ops and the original desktop renderer remains
available.
