# PowerShell helper script to run a flight test in CANYON and verify that
# the newly added procedural aircraft models appear in the log.
#
# Usage:
#   powershell.exe -ExecutionPolicy Bypass -File "C:\AI_Projektit\strike commander\test_flight_canyon.ps1"

$godotExe = "C:\\AI_Projektit\\strike commander\\tools\\godot\\Godot_v4.7.2-stable_win64.exe"
$logDir   = "C:\\Users\\mipoi\\AppData\\Roaming\\Godot\\app_userdata\\Strike Commander Reforged\\logs"
$logFile  = Join-Path $logDir "godot.log"

Write-Host "Starting Godot flight test..."
Start-Process -FilePath $godotExe -ArgumentList "--headless","--path","C:\\AI_Projektit\\strike commander\\game","--","--dir","C:/Gog games/Strike Commander","--auto=flight","--autopilot","--log","--frames=3600" -Wait

Write-Host "Flight test finished. Checking log for aircraft..."
$log = Get-Content $logFile
$matches = $log | Where-Object { $_ -match "F-16DES|MIG29|MIG21" }
if ($matches.Count -gt 0) {
    Write-Host "Detected aircraft in log:"
    $matches | ForEach-Object { Write-Host $_ }
    Write-Host "Test succeeded: new procedural aircraft are loaded."
} else {
    Write-Host "No known aircraft models found in log. Test failed."
}