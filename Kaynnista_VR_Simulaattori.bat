@echo off
rem Strike Commander Reforged - VR ilman lasteja (OpenXR Simulator).
rem Kayttaa projektin omaa simulaattoria vain talle prosessille;
rem koneen globaalia OpenXR-runtimea EI muuteta.
set "XR_RUNTIME_JSON=%~dp0tools\xr-simulator\openxr_simulator.json"
set "DIRARG="
if defined SC_GAME_DIR set DIRARG=--dir="%SC_GAME_DIR%"
"%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game" --vr %DIRARG% %*
