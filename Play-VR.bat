@echo off
title Gen1Recomp VR - OpenXR
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\run-vr.ps1"
if errorlevel 1 (
  echo.
  echo VR launch failed - see the error above.
  pause
)
