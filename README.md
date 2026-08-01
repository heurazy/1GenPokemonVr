# 1GenPokemonVR

**1GenPokemonVR** is an experimental Windows OpenXR edition of the Generation
1 recompilation. It combines the native game engine, a voxel overworld and a
custom stereo bridge. The overworld renders as real per-eye 3D geometry, while
menus and spatial battles use stable OpenXR composition layers.

This repository does not contain a Pokemon ROM or extracted copyrighted game
assets. Players must provide a legally obtained compatible US Pokemon Red or
Blue ROM during the first launch.

## VR highlights

- Native stereo OpenXR rendering with 6DoF head tracking.
- Meta Touch, Valve Index, HTC Vive and Windows Mixed Reality bindings.
- Ray pointer and draggable browser-style scrollbars in menus.
- Immersive, orbit, overhead and first-person cameras.
- Adjustable world scale, view distance, pitch, height, X/Z offset and head
  motion strength under **START -> VR OPTION**.
- Head-relative first-person movement: pushing forward moves in the direction
  you are looking, snapped to Pokemon's four-direction movement grid.
- Spatial battles with separate battlefield, opponent, attack, player and HUD
  depths. Important HP/name/status information always stays in front.

A native LÖVE2D recreation of Pokemon Red and Blue. The engine and map
behavior are hand-written Lua; game data and graphics are decoded from a ROM
supplied by the player.

SUPPORT AND ANNOUNCEMENTS: [Discord](https://bois.icu)

This project does not include a ROM, emulate the Game Boy, transpile assembly,
or download a disassembly. A canonical US Pokemon Red or Blue ROM is the only
game content input.

The ROM is verified, used during import, and then released from memory. It is
not copied into the cache. Later launches load the private generated cache and
do not ask for the ROM again. Red and Blue can both be imported and played
side by side.

## Quick Start

Open the desktop app. On first boot, choose your legally obtained `.gb` file
or drop it onto the window. Import takes a few seconds and the game starts
automatically.

Only the canonical 1 MiB US Red and Blue ROMs are accepted. The importer
verifies SHA-1 before creating any game data:

- Red: `ea9bcae617fdf159b045185467ae58b2e4a48b9a`
- Blue: `d7037c83e1ae5b39bde3c30787637ba1d4c48ce2`

The packaged app contains neither a ROM nor pre-extracted game data. Music,
sound effects, and cries are synthesized while the game runs from compact
audio channel programs copied out of the verified ROM.

## Controls

| Action | Keyboard | Controller |
|--------|----------|------------|
| Move | Arrow keys / WASD | D-pad / left stick |
| A | Z / Enter / Space | A |
| B | X / Backspace | B |
| Start | Escape | Start |
| Select | Tab / Shift | Back / Select |

Rebind any of these in-game under **OPTIONS → CONTROLS**. Controllers are
supported out of the box.

In VR, OpenXR maps Meta Touch, Valve Index, HTC Vive and Windows Mixed Reality
controllers (plus compatible runtime profiles) automatically: left stick
moves, trigger/A confirms, grip/B cancels, menu opens START, and the right
stick controls the orbit camera. Camera and comfort settings live under
**START -> VR OPTION**. See [docs/vr.md](docs/vr.md) for the full layout.
Point the right controller at a menu and use the trigger to select the row;
the pointer disappears automatically whenever no interactive menu is open.

### Hotkeys

| Key | What it does |
|-----|----------------|
| `-` / `=` | Zoom out / in (overworld; also mouse wheel) |
| `2` | Cycle COLORS |
| `3` | Cycle TILT (free-roam overworld) |
| `4` | Cycle ZOOM through every level (free-roam overworld) |
| `5` | Cycle GBC FX |
| `F1` | Save |
| `F2` | Load |
| `F10` | Open / close the mod manager |

COLORS, TILT, ZOOM, GBC FX, and VOID FILL are also in the Options menu
and persist in `options.lua`.

## Running From Source

Requires LÖVE 11.x. Place a Red or Blue ROM in the project folder and
double-click `Play-Mac.command` or `Play-Windows.bat`, or run:

```sh
scripts/setup.sh --rom "/path/to/Pokemon Red.gb"   # or Pokemon Blue.gb
scripts/run.sh
```

then `love .` for later launches. Windows PowerShell scripts, the optional
developer data build, test suites, and cache management are covered in
[Developer Setup](https://github.com/bryanthaboi/pokemon-gen1-recomp-project/wiki/Guide-Developer-Setup).

## Stereo VR (Windows / SteamVR)

This branch includes the Dramatic Shape voxel world and a native OpenXR
stereo path. After the normal first-run ROM import, start SteamVR and
double-click `Play-VR.bat`. The first launch builds the small OpenXR bridge;
later launches start directly. Press `F8` to recenter.

See [`docs/vr.md`](docs/vr.md) for prerequisites, build details, controls and
the renderer architecture.

## Portable Mode

By default the game keeps your save, options, and the private ROM-derived
data cache in your OS's normal per-user app data folder. To keep everything
next to the game instead (handy for a USB stick or portable drive you carry
between computers), drop an empty file named `portable.txt` next to the app
(next to `PokemonRed.app`/`.exe`, or next to `main.lua`/`conf.lua` when
running from source), then launch the game. Portable mode is desktop-only
(Windows, Linux, macOS); it has no effect on Android or iOS, where the app
runs from a read-only package.

With `portable.txt` present:

- `save.lua`, `save.lua.bak`, and `options.lua` are read from and written to
  that same folder instead of the OS save directory.
- A ROM import writes the generated `data/generated` and `assets/generated`
  cache straight into that folder too (nothing is left in the OS save
  directory), so a later launch reuses it without asking for the ROM again
  even on a different computer, as long as the same folder comes along.
- Deleting `portable.txt` switches back to the normal OS save directory; nothing
  already written to either location is touched automatically, so copy files
  over yourself if you want to carry existing progress across the switch.

## Modding

The game ships a native mod platform: content registries, events and hooks,
per-mod saves and options, and an in-game manager. The full modding book —
getting started, a twelve-rung tutorial ladder, a cookbook, and the generated
reference — lives on the
[project wiki](https://github.com/bryanthaboi/pokemon-gen1-recomp-project/wiki).

Shipped example mods, one per kind of author, live in [`mods/`](mods/).

## Bugs and Ideas

Found a bug? A warp dropping you somewhere it shouldn't, a battle doing math
that looks wrong, text in the wrong box, anything that does not match the
original game.
[Open a bug report](https://github.com/bryanthaboi/pokemon-gen1-recomp-project/issues/new?template=bug_report.yml).
Attach a screenshot if you can. It saves a lot of back and forth, and if you
can't get one, the form asks you to describe what you saw instead.

Thought of a feature that could be good, or a way to improve one that already
exists?
[Open a feature request](https://github.com/bryanthaboi/pokemon-gen1-recomp-project/issues/new?template=feature_request.yml).
Say what you want, why it is worth doing, and how you picture it working. A
request with real detail is one that can actually get built.

## More

- [Link play](https://github.com/bryanthaboi/pokemon-gen1-recomp-project/wiki/Guide-Link-Play)
  — START > LINK connects two copies directly over UDP.
- [Save editor](https://github.com/bryanthaboi/pokemon-gen1-recomp-project/wiki/Guide-Save-Editor)
  — edit party, boxes, items, events, and Pokédex flags outside the game.
- `docs/architecture.md` — runtime details;
  `docs/behavior-porting-notes.md` — formula provenance.

## Special Thanks

1GenPokemonVR is built on and must credit the following upstream work:

- [bryanthaboi/gen1recomp](https://github.com/bryanthaboi/gen1recomp) for the
  native Lua/LÖVE Generation 1 recompilation.
- [Dramatic Shape Voxel Mod v1.4.0](https://github.com/DramaticShape/DramaticShapeVoxelMod/releases/tag/v1.4.0)
  for the voxel-world project and visual foundation.

The OpenXR integration, VR input, spatial UI and layered battle presentation
are additions made for this project. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
before redistributing source or binaries.

This project would not be possible without [pret](https://github.com/pret) >
the pret band of decompiling maniacs > and their
[pokered](https://github.com/pret/pokered) disassembly.
