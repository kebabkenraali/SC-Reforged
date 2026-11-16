@echo off
set "GODOT=C:\AI_Projektit\strike commander\tools\godot\Godot_v4.7.2-stable_win64.exe"
set "GAME=C:\AI_Projektit\strike commander\game"
set "SHOT=C:\AI_Projektit\strike commander\demo\shot_test.png"
set "LOG=C:\AI_Projektit\strike commander\demo\log.txt"
"%GODOT%" --headless --path "%GAME%" --auto=flight --mission=MISSIONS/MISN-1A.IFF --autopilot --fast --shot="%SHOT%" --frames=120 --dir="C:\Gog games\Strike Commander" > "%LOG%" 2>&1
echo Exit code: %errorlevel%
