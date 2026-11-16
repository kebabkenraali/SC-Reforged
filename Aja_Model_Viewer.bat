@echo off
REM Strike Commander Reforged - Model Viewer
REM View any aircraft model from the original data

set "GODOT=C:\AI_Projektit\strike commander\engine\Godot_v4.7.2-stable_win64.exe"
set "GAME_PATH=C:\AI_Projektit\strike commander\game"
set "SC_DATA=C:\AI_Projektit\SC-REFORGED"

echo Starting MODEL VIEWER...
echo Game data: %SC_DATA%
echo Usage: Press keys to cycle models, mouse to rotate
echo.

"%GODOT%" --path "%GAME_PATH%" --auto=viewer --dir="%SC_DATA%"

echo.
echo Viewer closed.
pause