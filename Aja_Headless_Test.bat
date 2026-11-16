@echo off
REM Strike Commander Reforged - Headless Autopilot Test
REM Runs MISN-1A with autopilot at 10x speed, exits with code 0 on success

set "GODOT=C:\AI_Projektit\strike commander\engine\Godot_v4.7.2-stable_win64.exe"
set "GAME_PATH=C:\AI_Projektit\strike commander\game"
set "SC_DATA=C:\AI_Projektit\SC-REFORGED"

echo Starting HEADLESS test: MISN-1A with autopilot (10x speed)...
echo Game data: %SC_DATA%
echo.

"%GODOT%" --headless --path "%GAME_PATH%" --auto=campaign --autopilot --fast --timeout=300 --dir="%SC_DATA%"

set EXIT_CODE=%ERRORLEVEL%
echo.
if %EXIT_CODE%==0 (
    echo SUCCESS: Mission completed (landed safely)
) else if %EXIT_CODE%==3 (
    echo FAILED: Mission failed (shot down, crashed, or C-130 destroyed)
) else if %EXIT_CODE%==4 (
    echo TIMEOUT: Mission took too long
) else (
    echo ERROR: Exit code %EXIT_CODE%
)
pause
exit /b %EXIT_CODE%