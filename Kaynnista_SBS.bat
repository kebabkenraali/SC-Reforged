@echo off
rem Strike Commander Reforged - SBS (side-by-side) VR versio.
rem Kaikki renderoidaan stereona; 2D-valikot ja leikkaukset naytetaan
rem suurella maailmaan kiinnitetylla paneelilla, jonka ympari voi katsoa
rem istuen paikan paalla (paan seuranta).
rem Oletuksena kayttaa OpenXR Simulatoria (ilman VR-laseja).
rem Aidoilla laseilla kayta: Kaynnista_VR.bat --sbs
set "XR_RUNTIME_JSON=%~dp0tools\xr-simulator\openxr_simulator.json"
set "DIRARG="
if defined SC_GAME_DIR set DIRARG=--dir="%SC_GAME_DIR%"
"%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game" --vr --sbs %DIRARG% %*
