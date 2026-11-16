@echo off
REM Strike Commander Reforged - Full Game Launcher
REM Starts the main menu where you can choose New Campaign, Continue, Free Flight, etc.

set "GODOT=C:\AI_Projektit\strike commander\engine\Godot_v4.7.2-stable_win64.exe"
set "GAME_PATH=C:\AI_Projektit\strike commander\game"
set "SC_DATA=C:\AI_Projektit\SC-REFORGED"

echo Starting Strike Commander Reforged...
echo Game data: %SC_DATA%
echo.

"%GODOT%" --path "%GAME_PATH%" --dir="%SC_DATA%"

echo.
echo Game ended.
pause