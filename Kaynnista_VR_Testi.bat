@echo off
rem VR-testilento ilman vihollisia ja kuolemattomalla koneella.
rem Käyttää OpenXR Simulatoria (ei lasteja) vain tässä prosessissa.
set "XR_RUNTIME_JSON=%~dp0tools\xr-simulator\openxr_simulator.json"
set "DIRARG="
if defined SC_GAME_DIR set DIRARG=--dir="%SC_GAME_DIR%"
"%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game" --vr --auto=flight --no_enemies --god --endless_ammo %DIRARG% %*
