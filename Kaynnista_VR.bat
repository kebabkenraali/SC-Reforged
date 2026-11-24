@echo off
rem Strike Commander Reforged - VR-versio (OpenXR).
rem KOKO peli naykyy headsetissa: lento on oikeaa stereo-3D:aa,
rem valikot/keskustelut/leikkaukset litteana 2D-kuvana paan edessa.
rem Vaatii OpenXR-runtime:n ja yhdistetyn headsetin. Ilman niita peli
rem kaynnistyy normaalina desktop-tilana.
rem Pelidata: ymparistomuuttuja SC_GAME_DIR, muuten pelin oma automaattihaku.
set "DIRARG="
if defined SC_GAME_DIR set DIRARG=--dir="%SC_GAME_DIR%"
"%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game" --vr %DIRARG% %*
