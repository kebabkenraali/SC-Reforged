@echo off
REM Strike Commander Reforged - Demo Launcher

set GODOT=C:\AI_Projektit\strike commander\engine\Godot_v4.7.2-stable_win64.exe
set GAME_PATH=C:\AI_Projektit\strike commander\game
set SC_DATA=C:\AI_Projektit\SC-REFORGED

echo Starting Strike Commander Reforged - DEMO MODE...
echo Game data: %SC_DATA%

"%GODOT%" --path "%GAME_PATH%" --auto=campaign --dir="%SC_DATA%"

echo.
echo Demo ended.
pause
