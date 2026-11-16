@echo off
REM Strike Commander Reforged - Free Flight Test
REM Starts free flight in CANYON with F-16, no mission

set "GODOT=C:\AI_Projektit\strike commander\engine\Godot_v4.7.2-stable_win64.exe"
set "GAME_PATH=C:\AI_Projektit\strike commander\game"
set "SC_DATA=C:\AI_Projektit\SC-REFORGED"

echo Starting FREE FLIGHT in CANYON with F-16...
echo Game data: %SC_DATA%
echo.

"%GODOT%" --path "%GAME_PATH%" --auto=flight --map=CANYON --plane=OBJECTS/F-16DES.IFF --dir="%SC_DATA%"

echo.
echo Flight ended.
pause