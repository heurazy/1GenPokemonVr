# Standalone Meta Quest 3 / 3S preview

The Quest build runs directly on the headset. It does not use Quest Link,
SteamVR or a PC OpenXR runtime while playing.

## Install

1. Enable Developer Mode for the headset.
2. Connect it by USB and accept the debugging prompt.
3. Install `1GenPokemonVR-Quest3-v0.2.11.apk` with Meta Quest Developer Hub, or:

   ```sh
   adb install -r 1GenPokemonVR-Quest3-v0.2.11.apk
   ```

4. In the headset, open **Library -> Unknown Sources** and launch
   **1GenPokemonVR Quest**.
5. Point the right Touch controller at the first-run panel and choose a legally
   obtained compatible US Pokémon Red or Blue ROM. No ROM is shipped in the
   APK.

## VR options

Open **START -> VR OPTION** to move and resize the virtual world:

- **CAMERA** changes immersive, orbit, overhead or first-person presentation.
- **WORLD SCALE** changes the apparent size of the voxel world.
- **VIEW DISTANCE**, **VIEW PITCH** and **VIEW HEIGHT** place it in the room.
- **VIEW OFFSET X/Z** moves it sideways or forward/back.
- **RECENTER VIEW** creates a new local anchor in front of the player.

## Build

From PowerShell on Windows:

```powershell
.\scripts\build-quest.ps1 -Version 0.2.11 -Configuration Debug
```

The script packages a ROM-free payload, builds the Android ARM64 OpenXR/GLES
bridge, embeds the official Khronos OpenXR loader, builds LÖVE and writes the
APK under `dist/quest/`.

This is a developer-signed preview. Test performance and comfort on a physical
Quest 3/3S before wider redistribution.
