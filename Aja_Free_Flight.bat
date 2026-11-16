@echo off
rem Strike Commander Reforged - vapaa lento, CANYON, F-16
rem Pelidata: ymparistomuuttuja SC_GAME_DIR, muuten pelin oma automaattihaku.
set "DIRARG="
if defined SC_GAME_DIR set DIRARG=--dir="%SC_GAME_DIR%"
"%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game" --auto=flight --map=CANYON --plane=OBJECTS/F-16DES.IFF %DIRARG% %*
